import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/presentation/screens/add_up_screen.dart';
import 'package:esferaup/features/up/presentation/screens/up_edit_screen.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../golden/activa_golden_fixtures.dart';

void main() {
  for (final font in AppFontFamily.values) {
    for (final dark in [false, true]) {
      for (final edit in [false, true]) {
        testWidgets(
          '${edit ? "edit" : "capture"} ${font.name} dark=$dark at 200%',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(393, 852));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              ProviderScope(
                overrides: feedGoldenOverrides(),
                child: MaterialApp(
                  theme: dark ? AppTheme.dark(font) : AppTheme.light(font),
                  locale: const Locale('ca'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: edit
                      ? UpEditScreen(
                          detail: UpDetail(
                            id: 'up-1',
                            profileId: 'p1',
                            category: 'escola',
                            occurredAt: DateTime(2026, 6, 15),
                            isPinned: false,
                            isCrisi: false,
                            createdAt: DateTime(2026, 6, 15),
                          ),
                        )
                      : const AddUpScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (var page = 0; page < 4; page++) {
              await tester.drag(find.byType(ListView), const Offset(0, -400));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
}
