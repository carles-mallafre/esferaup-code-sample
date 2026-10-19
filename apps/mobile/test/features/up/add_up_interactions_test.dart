import 'dart:io';

import 'package:dio/dio.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:esferaup/core/upload/upload_transport.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/family/domain/entities/family.dart';
import 'package:esferaup/features/family/domain/entities/profile.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/notifications/presentation/providers/push_notification_controller.dart';
import 'package:esferaup/features/up/data/up_attachment_picker.dart';
import 'package:esferaup/features/up/data/up_audio_capture.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/entities/up_save_result.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_saved_screen.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_test/flutter_test.dart';

const _family = Family(
  id: 'family-1',
  profiles: [
    Profile(id: 'profile-1', displayName: 'Marc'),
    Profile(id: 'profile-2', displayName: 'Júlia'),
  ],
  puntsBalance: 0,
  tier: 'free',
  status: 'active',
);

class _AttachmentPicker implements UpAttachmentPicker {
  _AttachmentPicker(this.attachment);

  final PickedUpAttachment attachment;
  UpAttachmentPickSource? source;
  int calls = 0;

  @override
  Future<PickedUpAttachment?> pick(UpAttachmentPickSource source) async {
    calls++;
    this.source = source;
    return attachment;
  }
}

class _GrantedAudioPermission implements UpAudioPermissionGateway {
  @override
  Future<UpAudioPermissionState> check() async =>
      UpAudioPermissionState.granted;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<UpAudioPermissionState> request() async =>
      UpAudioPermissionState.granted;
}

class _CompletedAudioRecorder implements UpAudioRecorderBackend {
  _CompletedAudioRecorder(this.file);

  final File file;

  @override
  Stream<UpAudioBackendState> get states => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> cancel() async {
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<File> start() async {
    await file.writeAsBytes([1, 2, 3], flush: true);
    return file;
  }

  @override
  Future<File?> stop() async => file;
}

class _UploadTransport extends UploadTransport {
  _UploadTransport() : super(Dio());

  int calls = 0;
  String? profileId;
  String? context;
  String? mime;

  @override
  Future<PresignedUpload> uploadFile({
    required String context,
    required String profileId,
    required File file,
    required String mime,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    calls++;
    this.context = context;
    this.profileId = profileId;
    this.mime = mime;
    return PresignedUpload(
      uploadKey: 'upload-1',
      uploadUrl: Uri.parse('https://uploads.example.test/up'),
      expiresAt: DateTime.utc(2026, 8),
    );
  }
}

class _UpRepository implements UpRepository {
  _UpRepository({this.failuresRemaining = 0, this.createError});

  int failuresRemaining;
  final Object? createError;
  int createCalls = 0;
  String? profileId;
  List<String>? attachmentUploadKeys;
  bool? saveToArxiu;

  @override
  Future<UpSaveResult> createUp({
    required String profileId,
    required String category,
    required DateTime occurredAt,
    UpMood? mood,
    String? note,
    String? tag,
    List<String> attachmentUploadKeys = const [],
    bool saveToArxiu = false,
  }) async {
    createCalls++;
    this.profileId = profileId;
    this.attachmentUploadKeys = attachmentUploadKeys;
    this.saveToArxiu = saveToArxiu;
    if (createError != null) throw createError!;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('transient create failure');
    }
    return const UpSaveResult(
      id: 'up-created',
      puntsAwarded: 5,
      dailyCapReached: false,
    );
  }

  @override
  Future<UpDetail> updateUp({
    required String upId,
    required String category,
    required UpMood? mood,
    required String note,
    required String? tag,
  }) => throw UnimplementedError();

  @override
  Future<UpSaveResult> createCrisi({
    required String profileId,
    required DateTime occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    bool draft = false,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteUp(String upId) => throw UnimplementedError();

  @override
  Future<List<DeletedUp>> listDeletedUps(String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> restoreUp(String upId) => throw UnimplementedError();
  @override
  Future<UpDetail> updateCrisi({
    required String upId,
    DateTime? occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    required bool draft,
  }) => throw UnimplementedError();

  @override
  Future<UpAttachmentDownloadGrant> getAttachmentDownloadGrant({
    required String upId,
    required int attachmentIndex,
  }) => throw UnimplementedError();

  @override
  Future<UpDetail> getUp(String upId) => throw UnimplementedError();

  @override
  Future<bool> setPinned({required String upId, required bool pinned}) =>
      throw UnimplementedError();
}

class _NoPromptPushController extends PushNotificationController {
  @override
  PushRuntimeState build() => const PushRuntimeState();

  @override
  Future<bool> onFirstUpPersisted() async => false;
}

class _TempFiles extends SensitiveTempFileStore {
  _TempFiles()
    : super(
        tempDirectory: () async =>
            Directory('/private/tmp/esferaup_mobile_test'),
      );

  @override
  Future<void> delete(File file) async {}
}

Widget _host(
  Widget child,
  List<Override> overrides, {
  AppFontFamily font = AppFontFamily.lexend,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: locale,
    theme: AppTheme.light(font),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

void main() {
  for (final historyOnly in [false, true]) {
    for (final font in AppFontFamily.values) {
      testWidgets(
        'read-only UP entry protects drafting (history=$historyOnly, font=$font)',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(393, 1180));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repository = _UpRepository();
          await tester.pumpWidget(
            _host(
              const MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: AddUpScreen(),
              ),
              [
                currentFamilyProvider.overrideWith(
                  (ref) async => Family(
                    id: 'family-1',
                    profiles: [
                      Profile(
                        id: 'profile-1',
                        displayName: 'Marc',
                        role: historyOnly ? 'edit' : 'view_only',
                        accessScope: historyOnly ? 'history_only' : 'current',
                      ),
                      const Profile(
                        id: 'profile-2',
                        displayName: 'Júlia',
                        role: 'edit',
                      ),
                    ],
                    puntsBalance: 0,
                    tier: 'free',
                    status: 'active',
                  ),
                ),
                upRepositoryProvider.overrideWithValue(repository),
                sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
              ],
              font: font,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsNothing);
          expect(find.text('Save my UP'), findsNothing);
          expect(find.text('Photo'), findsNothing);
          expect(repository.createCalls, 0);
          await tester.tap(find.text('Marc').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Júlia').first);
          await tester.pumpAndSettle();
          expect(find.text('Save my UP'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'profile switch and PDF attachment reach the create-UP contract',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final picked = PickedUpAttachment(
        file: File(
          '/private/tmp/esferaup_mobile_test/esferaup_sensitive/report.pdf',
        ),
        mime: 'application/pdf',
        displayName: 'report.pdf',
      );
      final picker = _AttachmentPicker(picked);
      final transport = _UploadTransport();
      final repository = _UpRepository(failuresRemaining: 1);
      String? savedId;
      String? savedEsfera;

      await tester.pumpWidget(
        _host(
          AddUpScreen(
            onSaved: (id, esfera) {
              savedId = id;
              savedEsfera = esfera;
            },
          ),
          [
            currentFamilyProvider.overrideWith((ref) async => _family),
            upAttachmentPickerProvider.overrideWithValue(picker),
            uploadTransportProvider.overrideWithValue(transport),
            upRepositoryProvider.overrideWithValue(repository),
            sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
            pushNotificationControllerProvider.overrideWith(
              _NoPromptPushController.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marc'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Júlia'));
      await tester.pumpAndSettle();
      expect(find.text('Júlia'), findsOneWidget);

      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(find.text('report.pdf'), findsOneWidget);

      // A real attachment surfaces the Arxiu checkbox; the (i) sheet explains
      // the archive without toggling it.
      final arxiuRow = find.byKey(const ValueKey('add-up-save-to-arxiu'));
      expect(arxiuRow, findsOneWidget);
      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('What is the Archive?'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(arxiuRow).value, isFalse);
      await tester.tap(arxiuRow);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(arxiuRow).value, isTrue);

      await tester.tap(find.text('Save my UP'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(savedId, isNull);
      expect(transport.calls, 1);
      expect(repository.createCalls, 1);
      ScaffoldMessenger.of(
        tester.element(find.byType(AddUpScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save my UP'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(picker.source, UpAttachmentPickSource.pdf);
      expect(transport.context, 'up_document');
      expect(transport.profileId, 'profile-2');
      expect(transport.mime, 'application/pdf');
      expect(repository.profileId, 'profile-2');
      expect(repository.attachmentUploadKeys, const ['upload-1']);
      expect(repository.saveToArxiu, isTrue);
      expect(transport.calls, 1, reason: 'retry must reuse the uploaded key');
      expect(repository.createCalls, 2);
      expect(savedId, 'up-created');
      expect(savedEsfera, 'Emotions');
    },
  );

  testWidgets(
    'a refused profile write shows no connection error under its explanation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _UpRepository(
        createError: const MigrationLockedError(
          code: 'PROFILE_AWAITING_ADULT_CONSENT',
        ),
      );
      String? savedId;

      await tester.pumpWidget(
        _host(AddUpScreen(onSaved: (id, _) => savedId = id), [
          currentFamilyProvider.overrideWith((ref) async => _family),
          uploadTransportProvider.overrideWithValue(_UploadTransport()),
          upRepositoryProvider.overrideWithValue(repository),
          sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
          pushNotificationControllerProvider.overrideWith(
            _NoPromptPushController.new,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save my UP'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(repository.createCalls, 1);
      expect(savedId, isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Save my UP'))
            .onPressed,
        isNotNull,
        reason: 'the form stays usable after the refusal',
      );
    },
  );

  testWidgets('saved-UP actions are disabled unless a real callback exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var viewed = false;
    await tester.pumpWidget(
      _host(AddUpSavedScreen(onViewUp: () => viewed = true), const []),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View the created UP'));
    expect(viewed, isTrue);

    await tester.pumpWidget(_host(const AddUpSavedScreen(), const []));
    await tester.pumpAndSettle();
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'View the created UP'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('completed audio counts toward the five-attachment UI cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory directory;
    late UpAudioCaptureController audioController;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('add-up-audio-cap-');
      final audio = File('${directory.path}/voice.m4a');
      audioController = UpAudioCaptureController(
        permission: _GrantedAudioPermission(),
        recorder: _CompletedAudioRecorder(audio),
      );
      await audioController.initialize();
      await audioController.start();
      await audioController.stop();
    });
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final picker = _AttachmentPicker(
      PickedUpAttachment(
        file: File('${directory.path}/report.pdf'),
        mime: 'application/pdf',
        displayName: 'report.pdf',
      ),
    );

    await tester.pumpWidget(
      _host(const AddUpScreen(), [
        currentFamilyProvider.overrideWith((ref) async => _family),
        upAttachmentPickerProvider.overrideWithValue(picker),
        upAudioCaptureControllerProvider.overrideWith((ref) => audioController),
        sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
    }

    expect(picker.calls, 4);
    expect(find.text('report.pdf'), findsNWidgets(4));
    expect(
      find.text('You can add up to 5 attachments per UP.'),
      findsOneWidget,
    );
    await tester.runAsync(audioController.discard);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('attachment actions never break a label across lines', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(402, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(const AddUpScreen(), [
        currentFamilyProvider.overrideWith((ref) async => _family),
        sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
      ], locale: const Locale('es')),
    );
    await tester.pumpAndSettle();

    final lineHeight = tester.getSize(find.text('Guarda mi UP')).height;
    for (final label in ['Foto', 'Archivo', 'Audio']) {
      expect(
        tester.getSize(find.text(label)).height,
        lineHeight,
        reason: '$label wraps',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('closing with a recorded voice note', () {
    late Directory directory;
    late UpAudioCaptureController audioController;

    Future<void> record(WidgetTester tester) async {
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('add-up-close-');
        audioController = UpAudioCaptureController(
          permission: _GrantedAudioPermission(),
          recorder: _CompletedAudioRecorder(
            File('${directory.path}/voice.m4a'),
          ),
        );
        await audioController.initialize();
        await audioController.start();
        await audioController.stop();
      });
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
    }

    List<Override> overrides() => [
      currentFamilyProvider.overrideWith((ref) async => _family),
      upAudioCaptureControllerProvider.overrideWith((ref) => audioController),
      sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
    ];

    Future<void> tearDownScreen(WidgetTester tester) async {
      await tester.runAsync(audioController.discard);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets('the close button asks before discarding it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await record(tester);
      var closes = 0;
      await tester.pumpWidget(
        _host(AddUpScreen(onClose: () => closes++), overrides()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Discard the voice note?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closes, 0);
      expect(find.text('Voice note · 0s'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard'),
        ),
      );
      await tester.pumpAndSettle();
      expect(closes, 1);
      await tearDownScreen(tester);
    });

    testWidgets('the system back asks too', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await record(tester);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AddUpScreen()),
              ),
              child: const Text('open'),
            ),
          ),
          overrides(),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard the voice note?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddUpScreen), findsNothing);
    });

    testWidgets('without a voice note it closes at once', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var closes = 0;
      await tester.pumpWidget(
        _host(AddUpScreen(onClose: () => closes++), [
          currentFamilyProvider.overrideWith((ref) async => _family),
          sensitiveTempFileStoreProvider.overrideWithValue(_TempFiles()),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(closes, 1);
    });
  });
}
