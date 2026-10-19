import 'dart:async';

import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/home/data/home_actions_remote_datasource.dart';
import 'package:esferaup/features/home/presentation/providers/home_action_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_saved_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SavedUp extends UpDetailController {
  @override
  Future<UpDetail> build(String upId) async => UpDetail(
    id: upId,
    profileId: 'saved-profile',
    category: 'escola',
    occurredAt: DateTime(2026, 10, 10),
    createdAt: DateTime(2026, 10, 10),
    isPinned: false,
    isCrisi: false,
  );
}

RecordatoriDto reminder(bool enabled) => RecordatoriDto(
  enabled: enabled,
  timeOfDay: '21:30',
  tz: 'Europe/Madrid',
  includedProfiles: const ['saved-profile'],
);

Widget host({
  required Future<RecordatoriDto> settings,
  VoidCallback? later,
  VoidCallback? view,
}) => ProviderScope(
  overrides: [
    upDetailControllerProvider('saved-up').overrideWith(_SavedUp.new),
    recordatoriProvider('saved-profile').overrideWith((ref) => settings),
  ],
  child: MaterialApp(
    theme: AppTheme.light(AppFontFamily.lexend),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AddUpSavedScreen(
      upId: 'saved-up',
      onReminderLater: later,
      onViewUp: view,
    ),
  ),
);

void main() {
  testWidgets('Later dismisses reminder and keeps saved UP navigation', (
    tester,
  ) async {
    var dismissed = 0;
    var viewed = false;
    await tester.pumpWidget(
      host(
        settings: Future.value(reminder(false)),
        later: () => dismissed++,
        view: () => viewed = true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(find.text('Later'), findsNothing);
    await tester.tap(find.text('View the created UP'));
    expect(viewed, isTrue);
  });

  testWidgets('enabled reminder does not offer activation', (tester) async {
    await tester.pumpWidget(host(settings: Future.value(reminder(true))));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
    expect(find.text('View the created UP'), findsOneWidget);
  });

  testWidgets('waits for reminder state before offering activation', (
    tester,
  ) async {
    final settings = Completer<RecordatoriDto>();
    await tester.pumpWidget(host(settings: settings.future));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
    settings.complete(reminder(false));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsOneWidget);
  });
}
