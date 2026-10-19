import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_saved_screen.dart';
import 'package:esferaup/features/up/presentation/screens/crisi_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../golden/activa_golden_fixtures.dart';

void main() {
  for (final font in AppFontFamily.values) {
    for (final dark in [false, true]) {
      for (final crisis in [false, true]) {
        testWidgets(
          'capture auxiliary crisis=$crisis $font dark=$dark at 200%',
          (tester) async {
            tester.view.physicalSize = const Size(393, 852);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ProviderScope(
                overrides: feedGoldenOverrides(),
                child: MaterialApp(
                  theme: dark ? AppTheme.dark(font) : AppTheme.light(font),
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: crisis ? const CrisiScreen() : const AddUpSavedScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (crisis) {
              for (var i = 0; i < 4; i++) {
                await tester.drag(
                  find.byType(Scrollable).first,
                  const Offset(0, -350),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
            }
          },
        );
      }
    }
  }
}
