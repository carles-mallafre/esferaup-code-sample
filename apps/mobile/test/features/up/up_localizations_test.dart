import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UP categories and moods resolve in every supported locale', () async {
    final expectations = <String, (String, String)>{
      'ca': ('Escola', 'Enfadat'),
      'es': ('Escuela', 'Enfadado/a'),
      'en': ('School', 'Angry'),
    };

    for (final entry in expectations.entries) {
      final l10n = await AppLocalizations.delegate.load(Locale(entry.key));
      expect(upCategoryLabel(l10n, 'escola'), entry.value.$1);
      expect(upMoodLabel(l10n, UpMood.angry), entry.value.$2);
    }
  });

  test('unknown category preserves the server wire value', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(upCategoryLabel(l10n, 'future-category'), 'future-category');
  });
}
