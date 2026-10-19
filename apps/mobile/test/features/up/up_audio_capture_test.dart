import 'dart:async';
import 'dart:io';

import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:esferaup/features/up/data/up_audio_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _PermissionGateway implements UpAudioPermissionGateway {
  _PermissionGateway(
    this.current, [
    List<UpAudioPermissionState>? requests,
    this.checkError,
  ]) : requests = requests ?? [];

  UpAudioPermissionState current;
  final List<UpAudioPermissionState> requests;
  final Object? checkError;
  var requestCalls = 0;
  var settingsCalls = 0;

  @override
  Future<UpAudioPermissionState> check() async {
    if (checkError != null) throw checkError!;
    return current;
  }

  @override
  Future<UpAudioPermissionState> request() async {
    requestCalls++;
    if (requests.isNotEmpty) current = requests.removeAt(0);
    return current;
  }

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return true;
  }
}

class _RecorderBackend implements UpAudioRecorderBackend {
  _RecorderBackend(
    this.file, {
    this.available = true,
    this.startGate,
    this.startError,
    this.resumeError,
  });

  final File file;
  final bool available;
  final Completer<void>? startGate;
  final Object? startError;
  final Object? resumeError;
  final StreamController<UpAudioBackendState> _states =
      StreamController<UpAudioBackendState>.broadcast();
  var startCalls = 0;
  var stopCalls = 0;
  var pauseCalls = 0;
  var resumeCalls = 0;
  var cancelCalls = 0;

  @override
  Stream<UpAudioBackendState> get states => _states.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<File> start() async {
    startCalls++;
    await file.writeAsBytes([1, 2, 3], flush: true);
    if (startGate != null) await startGate!.future;
    if (startError != null) throw startError!;
    _states.add(UpAudioBackendState.recording);
    return file;
  }

  @override
  Future<File?> stop() async {
    stopCalls++;
    _states.add(UpAudioBackendState.stopped);
    return file;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _states.add(UpAudioBackendState.paused);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    if (resumeError != null) throw resumeError!;
    _states.add(UpAudioBackendState.recording);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (await file.exists()) await file.delete();
    _states.add(UpAudioBackendState.stopped);
  }

  @override
  Future<void> dispose() => _states.close();

  void emitError(Object error) => _states.addError(error);
}

Future<File> _recordingFile() async {
  final directory = await Directory.systemTemp.createTemp('esferaup-audio-');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return File('${directory.path}/voice.m4a');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('denial stays truthful and a later retry can grant', () async {
    final permission = _PermissionGateway(
      UpAudioPermissionState.notDetermined,
      [UpAudioPermissionState.denied, UpAudioPermissionState.granted],
    );
    final recorder = _RecorderBackend(await _recordingFile());
    final controller = UpAudioCaptureController(
      permission: permission,
      recorder: recorder,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.state.permission, UpAudioPermissionState.notDetermined);

    expect(await controller.requestPermission(), UpAudioPermissionState.denied);
    expect(controller.state.permission, UpAudioPermissionState.denied);
    expect(recorder.startCalls, 0);

    expect(
      await controller.requestPermission(),
      UpAudioPermissionState.granted,
    );
    await controller.start();
    expect(controller.state.phase, UpAudioCapturePhase.recording);
    expect(recorder.startCalls, 1);
  });

  test('a start right after the system permission prompt waits for the app '
      'to come back instead of silently doing nothing', () async {
    final permission = _PermissionGateway(
      UpAudioPermissionState.notDetermined,
      [UpAudioPermissionState.granted],
    );
    final recorder = _RecorderBackend(await _recordingFile());
    final controller = UpAudioCaptureController(
      permission: permission,
      recorder: recorder,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    // The system dialog makes the app inactive; the grant can be delivered
    // before the app is resumed.
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(
      await controller.requestPermission(),
      UpAudioPermissionState.granted,
    );
    final starting = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await starting;

    expect(controller.state.phase, UpAudioCapturePhase.recording);
    expect(recorder.startCalls, 1);
  });

  test('recording stops into one uploadable AAC attachment', () async {
    final permission = _PermissionGateway(UpAudioPermissionState.granted);
    final recorder = _RecorderBackend(await _recordingFile());
    final controller = UpAudioCaptureController(
      permission: permission,
      recorder: recorder,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.start();
    await controller.stop();

    expect(controller.state.phase, UpAudioCapturePhase.completed);
    expect(controller.state.completed?.mime, 'audio/mp4');
    expect(controller.state.completed?.uploadContext, 'up_audio');
    expect(await controller.state.completed!.file.length(), 3);
  });

  test(
    'device interruption pauses and can resume without a new file',
    () async {
      final recorder = _RecorderBackend(await _recordingFile());
      final controller = UpAudioCaptureController(
        permission: _PermissionGateway(UpAudioPermissionState.granted),
        recorder: recorder,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.start();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, UpAudioCapturePhase.interrupted);
      expect(recorder.pauseCalls, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await controller.resume();
      expect(controller.state.phase, UpAudioCapturePhase.recording);
      expect(recorder.resumeCalls, 1);
      expect(recorder.startCalls, 1);
    },
  );

  test(
    'account switch cancels capture and removes its plaintext bytes',
    () async {
      final file = await _recordingFile();
      final recorder = _RecorderBackend(file);
      final controller = UpAudioCaptureController(
        permission: _PermissionGateway(UpAudioPermissionState.granted),
        recorder: recorder,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.start();
      expect(await file.exists(), isTrue);

      await controller.cancelForSessionTransition();

      expect(recorder.cancelCalls, 1);
      expect(await file.exists(), isFalse);
      expect(controller.state.completed, isNull);
      expect(controller.state.phase, UpAudioCapturePhase.idle);
    },
  );

  test(
    'restart cleanup removes orphan audio before enabling new writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'esferaup-restart-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = SensitiveTempFileStore(
        tempDirectory: () async => directory,
      );
      final orphan = await store.allocate(extension: 'm4a');
      await orphan.writeAsBytes([1, 2, 3]);

      await prepareSensitiveTempStoreForAuthenticatedStartup(store);

      expect(await orphan.exists(), isFalse);
      final next = await store.allocate(extension: 'm4a');
      expect(next.parent.path, orphan.parent.path);
    },
  );

  test(
    'missing recorder capability fails closed without a permission prompt',
    () async {
      final permission = _PermissionGateway(
        UpAudioPermissionState.notDetermined,
      );
      final controller = UpAudioCaptureController(
        permission: permission,
        recorder: _RecorderBackend(await _recordingFile(), available: false),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state.phase, UpAudioCapturePhase.unavailable);
      expect(permission.requestCalls, 0);
    },
  );

  test('permission status failure leaves initialization unavailable', () async {
    final controller = UpAudioCaptureController(
      permission: _PermissionGateway(
        UpAudioPermissionState.notDetermined,
        const [],
        StateError('native permission service failed'),
      ),
      recorder: _RecorderBackend(await _recordingFile()),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state.phase, UpAudioCapturePhase.unavailable);
  });

  test('backgrounding during native start cancels the new recording', () async {
    final gate = Completer<void>();
    final file = await _recordingFile();
    final recorder = _RecorderBackend(file, startGate: gate);
    final controller = UpAudioCaptureController(
      permission: _PermissionGateway(UpAudioPermissionState.granted),
      recorder: recorder,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final starting = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.phase, UpAudioCapturePhase.checking);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    gate.complete();
    await starting;

    expect(recorder.cancelCalls, 1);
    expect(await file.exists(), isFalse);
    expect(controller.state.phase, UpAudioCapturePhase.idle);
  });

  test(
    'start failure cancels native state and removes plaintext bytes',
    () async {
      final file = await _recordingFile();
      final recorder = _RecorderBackend(
        file,
        startError: StateError('native start failed after allocation'),
      );
      final controller = UpAudioCaptureController(
        permission: _PermissionGateway(UpAudioPermissionState.granted),
        recorder: recorder,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.start();

      expect(recorder.cancelCalls, 1);
      expect(await file.exists(), isFalse);
      expect(controller.state.phase, UpAudioCapturePhase.failed);
    },
  );

  test(
    'resume failure cancels native state and removes plaintext bytes',
    () async {
      final file = await _recordingFile();
      final recorder = _RecorderBackend(
        file,
        resumeError: StateError('native resume failed'),
      );
      final controller = UpAudioCaptureController(
        permission: _PermissionGateway(UpAudioPermissionState.granted),
        recorder: recorder,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.start();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await controller.resume();

      expect(recorder.cancelCalls, 1);
      expect(await file.exists(), isFalse);
      expect(controller.state.phase, UpAudioCapturePhase.failed);
    },
  );

  test(
    'backend stream failure fails closed and removes plaintext bytes',
    () async {
      final file = await _recordingFile();
      final recorder = _RecorderBackend(file);
      final controller = UpAudioCaptureController(
        permission: _PermissionGateway(UpAudioPermissionState.granted),
        recorder: recorder,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.start();

      final failed = Completer<void>();
      void observeFailure() {
        if (controller.state.phase == UpAudioCapturePhase.failed &&
            !failed.isCompleted) {
          failed.complete();
        }
      }

      controller.addListener(observeFailure);
      addTearDown(() => controller.removeListener(observeFailure));
      recorder.emitError(StateError('native state stream failed'));
      await failed.future.timeout(const Duration(seconds: 2));

      expect(recorder.cancelCalls, 1);
      expect(await file.exists(), isFalse);
      expect(controller.state.phase, UpAudioCapturePhase.failed);
    },
  );
}
