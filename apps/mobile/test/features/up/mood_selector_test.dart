/// The mood row at default and 200% text: every label stays on one line (no
/// mid-word break) and the five faces share a top edge, in every locale, with
/// the mood words and with the longer observation-reaction words.
library;

import 'package:esferaup/core/theme/app_theme.dart';
import 'package:esferaup/core/theme/app_typography.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_selector.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

String _reactionLabel(AppLocalizations l10n, UpMood mood) => switch (mood) {
  UpMood.good => l10n.observationReactionHappy,
  UpMood.great => l10n.observationReactionLove,
  UpMood.sad => l10n.observationReactionSad,
  UpMood.angry => l10n.observationReactionAngry,
  UpMood.excited => l10n.observationReactionSpark,
};

void main() {
  for (final locale in ['ca', 'es', 'en']) {
    for (final font in AppFontFamily.values) {
      for (final reactions in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '$locale ${font.name} ${reactions ? "reactions" : "moods"}: '
            'one-line labels at ${scale}x',
            (tester) async {
              await tester.binding.setSurfaceSize(const Size(393, 852));
              addTearDown(() => tester.binding.setSurfaceSize(null));
              UpMood? picked;
              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(locale),
                  theme: AppTheme.light(font),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) => MoodSelector(
                          selected: UpMood.angry,
                          onChanged: (m) => picked = m,
                          labelBuilder: reactions
                              ? (mood) => _reactionLabel(
                                  AppLocalizations.of(context),
                                  mood,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);

              final labels = find.descendant(
                of: find.descendant(
                  of: find.byType(MoodSelector),
                  matching: find.byType(Text),
                ),
                matching: find.byType(RichText),
              );
              expect(labels, findsNWidgets(UpMood.values.length));
              for (final element in labels.evaluate()) {
                final paragraph = element.renderObject! as RenderParagraph;
                final label = paragraph.text.toPlainText();
                final lineTops = paragraph
                    .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: label.length),
                    )
                    .map((box) => box.top.round())
                    .toSet();
                expect(lineTops, hasLength(1), reason: label);
                expect(paragraph.didExceedMaxLines, isFalse);
              }

              final faceTops = find
                  .descendant(
                    of: find.byType(MoodSelector),
                    matching: find.byType(DecoratedBox),
                  )
                  .evaluate()
                  .map(
                    (e) => (e.renderObject! as RenderBox)
                        .localToGlobal(Offset.zero)
                        .dy,
                  )
                  .toSet();
              expect(faceTops, hasLength(1));

              final item = find
                  .descendant(
                    of: find.byType(MoodSelector),
                    matching: find.byType(GestureDetector),
                  )
                  .first;
              final size = tester.getSize(item);
              expect(size.width, greaterThanOrEqualTo(44));
              expect(size.height, greaterThanOrEqualTo(44));
              await tester.tap(item);
              expect(picked, UpMood.values.first);
              if (reactions) {
                final l10n = await AppLocalizations.delegate.load(
                  Locale(locale),
                );
                expect(
                  find.bySemanticsLabel(l10n.observationReactionSpark),
                  findsOneWidget,
                );
              }
            },
          );
        }
      }
    }
  }
}
