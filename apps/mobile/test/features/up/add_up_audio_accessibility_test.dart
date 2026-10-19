import 'dart:io';

import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/features/family/domain/entities/family.dart';
import 'package:esferaup/features/family/domain/entities/profile.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/up/data/up_audio_capture.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_test/flutter_test.dart';

class _BlockedPermission implements UpAudioPermissionGateway {
  @override
  Future<UpAudioPermissionState> check() async =>
      UpAudioPermissionState.permanentlyDenied;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<UpAudioPermissionState> request() async =>
      UpAudioPermissionState.permanentlyDenied;
}

class _AvailableRecorder implements UpAudioRecorderBackend {
  @override
  Stream<UpAudioBackendState> get states => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<File> start() => throw UnimplementedError();

  @override
  Future<File?> stop() => throw UnimplementedError();
}

void main() {
  testWidgets('permanently denied microphone remains actionable at 200% text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = UpAudioCaptureController(
      permission: _BlockedPermission(),
      recorder: _AvailableRecorder(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentFamilyProvider.overrideWith(
            (ref) => const Family(
              id: 'family-1',
              profiles: [Profile(id: 'profile-1', displayName: 'Marc')],
              puntsBalance: 0,
              tier: 'free',
              status: 'active',
            ),
          ),
          upAudioCaptureControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.light(AppFontFamily.lexend),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const AddUpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final audioButton = find.byWidgetPredicate(
      (widget) => widget is AppButton && widget.label == 'Audio',
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      audioButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(audioButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Turn on the microphone in Settings'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final photo = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == 'Photo',
            skipOffstage: false,
          )
          .first,
    );
    final file = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == 'File',
            skipOffstage: false,
          )
          .first,
    );
    final audio = tester.getRect(audioButton.first);
    expect(photo.top, lessThan(file.top));
    expect(file.top, lessThan(audio.top));
  });
}
