/// When a voice note starts recording, its panel (time, Stop, Discard) is
/// scrolled into view above the bottom action bar instead of staying hidden
/// below it.
library;

import 'dart:async';
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

class _GrantedPermission implements UpAudioPermissionGateway {
  @override
  Future<UpAudioPermissionState> check() async =>
      UpAudioPermissionState.granted;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<UpAudioPermissionState> request() async =>
      UpAudioPermissionState.granted;
}

class _Recorder implements UpAudioRecorderBackend {
  final _states = StreamController<UpAudioBackendState>.broadcast();

  @override
  Stream<UpAudioBackendState> get states => _states.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async => _states.close();

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<File> start() async {
    _states.add(UpAudioBackendState.recording);
    return File('${Directory.systemTemp.path}/qa-note.m4a');
  }

  @override
  Future<File?> stop() async => null;
}

void main() {
  testWidgets('the recording panel is visible above the save bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = UpAudioCaptureController(
      permission: _GrantedPermission(),
      recorder: _Recorder(),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final stop = find.text('Stop');
    expect(stop, findsOneWidget);
    final save = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) => widget is AppButton && widget.label == 'Save my UP',
          )
          .first,
    );
    expect(tester.getRect(stop).bottom, lessThanOrEqualTo(save.top));
  });
}
