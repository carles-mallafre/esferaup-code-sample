import 'dart:async';
import 'dart:io';

import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:esferaup/features/up/data/up_attachment_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UpAudioPermissionState {
  notDetermined,
  denied,
  permanentlyDenied,
  granted,
}

enum UpAudioCapturePhase {
  checking,
  idle,
  requestingPermission,
  recording,
  interrupted,
  completed,
  unavailable,
  failed,
}

enum UpAudioBackendState { recording, paused, stopped }

@immutable
class UpAudioCaptureState {
  const UpAudioCaptureState({
    this.permission = UpAudioPermissionState.notDetermined,
    this.phase = UpAudioCapturePhase.idle,
    this.elapsed = Duration.zero,
    this.completed,
  });

  final UpAudioPermissionState permission;
  final UpAudioCapturePhase phase;
  final Duration elapsed;
  final PickedUpAttachment? completed;

  UpAudioCaptureState copyWith({
    UpAudioPermissionState? permission,
    UpAudioCapturePhase? phase,
    Duration? elapsed,
    PickedUpAttachment? completed,
    bool clearCompleted = false,
  }) => UpAudioCaptureState(
    permission: permission ?? this.permission,
    phase: phase ?? this.phase,
    elapsed: elapsed ?? this.elapsed,
    completed: clearCompleted ? null : completed ?? this.completed,
  );
}

abstract interface class UpAudioPermissionGateway {
  Future<UpAudioPermissionState> check();
  Future<UpAudioPermissionState> request();
  Future<bool> openSettings();
}

abstract interface class UpAudioRecorderBackend {
  Stream<UpAudioBackendState> get states;
  Future<bool> isAvailable();
  Future<File> start();
  Future<File?> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> cancel();
  Future<void> dispose();
}

class NativeUpAudioPermissionGateway implements UpAudioPermissionGateway {
  // TODO(DPIA): Reconfirm the microphone-purpose wording and retained audio data
  // flow before production credentials and store privacy declarations are signed.
  NativeUpAudioPermissionGateway(this._preferences);

  static const _requestedKey = 'microphone_permission_requested_v1';
  final SharedPreferences Function() _preferences;

  @override
  Future<UpAudioPermissionState> check() async {
    final status = await Permission.microphone.status;
    return _map(
      status,
      requestedBefore: _preferences().getBool(_requestedKey) ?? false,
    );
  }

  @override
  Future<UpAudioPermissionState> request() async {
    if (!await _preferences().setBool(_requestedKey, true)) {
      throw StateError('Microphone permission history could not be stored.');
    }
    return _map(await Permission.microphone.request(), requestedBefore: true);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  UpAudioPermissionState _map(
    PermissionStatus status, {
    required bool requestedBefore,
  }) {
    if (status.isGranted) return UpAudioPermissionState.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return UpAudioPermissionState.permanentlyDenied;
    }
    return requestedBefore
        ? UpAudioPermissionState.denied
        : UpAudioPermissionState.notDetermined;
  }
}

class NativeUpAudioRecorderBackend implements UpAudioRecorderBackend {
  NativeUpAudioRecorderBackend(
    this._tempFiles, {
    AudioRecorder Function()? recorder,
  }) : _recorderFactory = recorder ?? AudioRecorder.new;

  final SensitiveTempFileStore _tempFiles;
  final AudioRecorder Function() _recorderFactory;
  final StreamController<UpAudioBackendState> _states =
      StreamController<UpAudioBackendState>.broadcast();
  AudioRecorder? _recorder;
  StreamSubscription<RecordState>? _stateSubscription;
  File? _destination;

  AudioRecorder _instance() {
    final existing = _recorder;
    if (existing != null) return existing;
    final recorder = _recorderFactory();
    _recorder = recorder;
    _stateSubscription = recorder.onStateChanged().listen((state) {
      _states.add(switch (state) {
        RecordState.record => UpAudioBackendState.recording,
        RecordState.pause => UpAudioBackendState.paused,
        RecordState.stop => UpAudioBackendState.stopped,
      });
    }, onError: _states.addError);
    return recorder;
  }

  @override
  Stream<UpAudioBackendState> get states => _states.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _instance().isEncoderSupported(AudioEncoder.aacLc);
    } on Object {
      return false;
    }
  }

  @override
  Future<File> start() async {
    if (_destination != null) await _abortRecording();
    final destination = await _tempFiles.allocate(extension: 'm4a');
    _destination = destination;
    try {
      await _instance().start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
          audioInterruption: AudioInterruptionMode.pause,
        ),
        path: destination.path,
      );
      return destination;
    } on Object {
      await _abortRecording();
      rethrow;
    }
  }

  @override
  Future<File?> stop() async {
    final destination = _destination;
    late final String? returnedPath;
    try {
      returnedPath = await _instance().stop();
      _destination = null;
    } on Object {
      await _abortRecording();
      rethrow;
    }
    if (returnedPath == null || destination == null) {
      if (destination != null) await _tempFiles.delete(destination);
      if (returnedPath != null) await _tempFiles.delete(File(returnedPath));
      return null;
    }
    final returned = File(returnedPath);
    if (returned.path != destination.path) {
      await _tempFiles.delete(destination);
      await _tempFiles.delete(returned);
      return null;
    }
    return returned;
  }

  @override
  Future<void> pause() => _instance().pause();

  @override
  Future<void> resume() => _instance().resume();

  @override
  Future<void> cancel() async {
    final destination = _destination;
    try {
      await _recorder?.cancel();
    } on Object {
      await _resetRecorder();
      rethrow;
    } finally {
      _destination = null;
      if (destination != null) await _tempFiles.delete(destination);
    }
  }

  @override
  Future<void> dispose() async {
    final destination = _destination;
    if (destination != null) {
      try {
        await _recorder?.cancel();
      } on Object {
        // Disposing the native recorder below is the final resource boundary.
      } finally {
        _destination = null;
        await _tempFiles.delete(destination);
      }
    }
    await _stateSubscription?.cancel();
    await _recorder?.dispose();
    await _states.close();
  }

  Future<void> _abortRecording() async {
    final destination = _destination;
    try {
      await _recorder?.cancel();
    } on Object {
      await _resetRecorder();
    } finally {
      _destination = null;
      if (destination != null) await _tempFiles.delete(destination);
    }
  }

  Future<void> _resetRecorder() async {
    await _stateSubscription?.cancel();
    try {
      await _recorder?.dispose();
    } on Object {
      // The failed platform recorder is abandoned and never reused.
    }
    _stateSubscription = null;
    _recorder = null;
  }
}

class UpAudioCaptureController extends ChangeNotifier
    with WidgetsBindingObserver {
  UpAudioCaptureController({
    required UpAudioPermissionGateway permission,
    required UpAudioRecorderBackend recorder,
    Duration maxDuration = const Duration(seconds: 60),
  }) : _permission = permission,
       _recorder = recorder,
       _maxDuration = maxDuration {
    _backendSubscription = _recorder.states.listen(
      _onBackendState,
      onError: (_) => _scheduleFailClosed(),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  final UpAudioPermissionGateway _permission;
  final UpAudioRecorderBackend _recorder;
  final Duration _maxDuration;
  late final StreamSubscription<UpAudioBackendState> _backendSubscription;
  UpAudioCaptureState _state = const UpAudioCaptureState();
  Timer? _timer;
  Future<void> _operationTail = Future<void>.value();
  int _generation = 0;
  bool _finishing = false;
  bool _disposed = false;
  bool _isForeground = true;
  bool _startInFlight = false;
  Completer<void>? _foregroundWaiter;

  UpAudioCaptureState get state => _state;

  Future<void> initialize() => _serialized(() async {
    _setState(_state.copyWith(phase: UpAudioCapturePhase.checking));
    try {
      if (!await _recorder.isAvailable()) {
        _setState(_state.copyWith(phase: UpAudioCapturePhase.unavailable));
        return;
      }
      final permission = await _permission.check();
      _setState(
        _state.copyWith(
          permission: permission,
          phase: _phaseForPermission(permission),
        ),
      );
    } on Object {
      _setState(_state.copyWith(phase: UpAudioCapturePhase.unavailable));
    }
  });

  Future<UpAudioPermissionState> requestPermission() async {
    var result = _state.permission;
    await _serialized(() async {
      _setState(
        _state.copyWith(phase: UpAudioCapturePhase.requestingPermission),
      );
      try {
        result = await _permission.request();
        _setState(
          _state.copyWith(
            permission: result,
            phase: _phaseForPermission(result),
          ),
        );
      } on Object {
        _setState(_state.copyWith(phase: UpAudioCapturePhase.unavailable));
      }
    });
    return result;
  }

  Future<void> refreshPermission() => _serialized(() async {
    if (_state.phase == UpAudioCapturePhase.recording ||
        _state.phase == UpAudioCapturePhase.interrupted) {
      return;
    }
    try {
      final permission = await _permission.check();
      _setState(
        _state.copyWith(
          permission: permission,
          phase: _state.completed == null
              ? _phaseForPermission(permission)
              : UpAudioCapturePhase.completed,
        ),
      );
    } on Object {
      _setState(_state.copyWith(phase: UpAudioCapturePhase.unavailable));
    }
  });

  Future<bool> openSettings() => _permission.openSettings();

  Future<void> start() => _serialized(() async {
    // The system permission prompt makes the app inactive, and the grant can
    // arrive before the app is resumed: wait for it briefly instead of
    // ignoring the start the adult just asked for.
    if (!_isForeground) await _awaitForeground(const Duration(seconds: 2));
    if (_state.permission != UpAudioPermissionState.granted ||
        _state.phase != UpAudioCapturePhase.idle ||
        !_isForeground) {
      return;
    }
    final generation = ++_generation;
    _startInFlight = true;
    _setState(
      _state.copyWith(
        phase: UpAudioCapturePhase.checking,
        elapsed: Duration.zero,
        clearCompleted: true,
      ),
    );
    try {
      await _recorder.start();
      if (generation != _generation || !_isForeground) {
        final cleaned = await _cleanupCaptureResources();
        _setState(
          UpAudioCaptureState(
            permission: _state.permission,
            phase: cleaned
                ? _phaseForPermission(_state.permission)
                : UpAudioCapturePhase.failed,
          ),
        );
        return;
      }
      _setState(
        _state.copyWith(
          phase: UpAudioCapturePhase.recording,
          elapsed: Duration.zero,
          clearCompleted: true,
        ),
      );
      _startTimer(generation);
    } on Object {
      await _cancelAndMarkFailed();
    } finally {
      _startInFlight = false;
    }
  });

  Future<void> stop() => _serialized(() async {
    if (_state.phase != UpAudioCapturePhase.recording &&
        _state.phase != UpAudioCapturePhase.interrupted) {
      return;
    }
    _timer?.cancel();
    _finishing = true;
    try {
      final file = await _recorder.stop();
      if (file == null || !await file.exists() || await file.length() == 0) {
        if (file != null) await file.delete().catchError((_) => file);
        await _cancelAndMarkFailed();
        return;
      }
      _setState(
        _state.copyWith(
          phase: UpAudioCapturePhase.completed,
          completed: PickedUpAttachment(
            file: file,
            mime: 'audio/mp4',
            displayName: 'audio-note.m4a',
          ),
        ),
      );
    } on Object {
      await _cancelAndMarkFailed();
    } finally {
      _finishing = false;
    }
  });

  Future<void> resume() => _serialized(() async {
    if (_state.phase != UpAudioCapturePhase.interrupted ||
        _state.permission != UpAudioPermissionState.granted ||
        !_isForeground) {
      return;
    }
    final generation = _generation;
    try {
      await _recorder.resume();
      if (generation != _generation) return;
      _setState(_state.copyWith(phase: UpAudioCapturePhase.recording));
      _startTimer(generation);
    } on Object {
      await _cancelAndMarkFailed();
    }
  });

  Future<void> discard() => _serialized(() async {
    _generation++;
    _timer?.cancel();
    final cleaned = await _cleanupCaptureResources();
    _setState(
      UpAudioCaptureState(
        permission: _state.permission,
        phase: cleaned
            ? _phaseForPermission(_state.permission)
            : UpAudioCapturePhase.failed,
      ),
    );
  });

  Future<void> cancelForSessionTransition() => discard();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isForeground = false;
      if (_startInFlight) _generation++;
      if (_state.phase == UpAudioCapturePhase.recording) {
        unawaited(_interrupt());
      }
    } else if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _foregroundWaiter?.complete();
      _foregroundWaiter = null;
      unawaited(refreshPermission());
    } else if (state == AppLifecycleState.detached) {
      _isForeground = false;
      if (_startInFlight) _generation++;
      unawaited(discard());
    }
  }

  Future<void> _awaitForeground(Duration limit) async {
    final waiter = _foregroundWaiter ??= Completer<void>();
    await waiter.future.timeout(limit, onTimeout: () {});
  }

  Future<void> _interrupt() => _serialized(() async {
    if (_state.phase != UpAudioCapturePhase.recording) return;
    _timer?.cancel();
    try {
      await _recorder.pause();
      _setState(_state.copyWith(phase: UpAudioCapturePhase.interrupted));
    } on Object {
      await _cancelAndMarkFailed();
    }
  });

  void _onBackendState(UpAudioBackendState backendState) {
    if (_disposed || _finishing) return;
    if (backendState == UpAudioBackendState.paused &&
        _state.phase == UpAudioCapturePhase.recording) {
      _timer?.cancel();
      _setState(_state.copyWith(phase: UpAudioCapturePhase.interrupted));
    } else if (backendState == UpAudioBackendState.stopped &&
        (_state.phase == UpAudioCapturePhase.recording ||
            _state.phase == UpAudioCapturePhase.interrupted)) {
      unawaited(discard());
    }
  }

  void _scheduleFailClosed() {
    if (_disposed) return;
    _generation++;
    unawaited(_serialized(_cancelAndMarkFailed));
  }

  void _startTimer(int expectedGeneration) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed ||
          expectedGeneration != _generation ||
          _state.phase != UpAudioCapturePhase.recording) {
        _timer?.cancel();
        return;
      }
      final elapsed = _state.elapsed + const Duration(seconds: 1);
      _setState(_state.copyWith(elapsed: elapsed));
      if (elapsed >= _maxDuration) {
        _timer?.cancel();
        unawaited(stop());
      }
    });
  }

  UpAudioCapturePhase _phaseForPermission(UpAudioPermissionState permission) =>
      switch (permission) {
        UpAudioPermissionState.granted => UpAudioCapturePhase.idle,
        UpAudioPermissionState.notDetermined ||
        UpAudioPermissionState.denied ||
        UpAudioPermissionState.permanentlyDenied => UpAudioCapturePhase.idle,
      };

  Future<void> _cancelAndMarkFailed() async {
    _generation++;
    _timer?.cancel();
    await _cleanupCaptureResources();
    _setState(
      UpAudioCaptureState(
        permission: _state.permission,
        phase: UpAudioCapturePhase.failed,
      ),
    );
  }

  Future<bool> _cleanupCaptureResources() async {
    var cleaned = true;
    final completed = _state.completed;
    _finishing = true;
    try {
      await _recorder.cancel();
    } on Object {
      cleaned = false;
    } finally {
      _finishing = false;
    }
    if (completed != null) {
      try {
        if (await completed.file.exists()) await completed.file.delete();
      } on FileSystemException {
        cleaned = false;
      }
    }
    return cleaned;
  }

  void _setState(UpAudioCaptureState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    try {
      await _operationTail;
    } on Object {
      // Resource disposal still proceeds after a failed capture operation.
    }
    try {
      await _backendSubscription.cancel();
    } on Object {
      // The backend remains the final native-resource cleanup boundary.
    }
    try {
      await _recorder.dispose();
    } on Object {
      // Disposal runs after UI ownership has ended and must not escape async.
    }
  }
}
