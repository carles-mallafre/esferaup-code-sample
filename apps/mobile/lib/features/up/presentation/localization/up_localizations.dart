import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/l10n/app_localizations.dart';

String upCategoryLabel(AppLocalizations l10n, String key) => switch (key) {
  'casa' => l10n.upCategoryHome,
  'escola' => l10n.upCategorySchool,
  'emocions' => l10n.upCategoryEmotions,
  'esport' => l10n.upCategorySport,
  'salut' => l10n.upCategoryHealth,
  'activa' => l10n.upCategoryActiva,
  'nutricio' => l10n.upCategoryNutrition,
  'descans' => l10n.upCategoryRest,
  _ => key,
};

/// The one-line gloss under a category name — what a place would actually read
/// there. Figma `1436:33241` shows them on the permission matrix.
String upCategoryDescription(AppLocalizations l10n, String key) =>
    switch (key) {
      'casa' => l10n.upCategoryDescHome,
      'escola' => l10n.upCategoryDescSchool,
      'emocions' => l10n.upCategoryDescEmotions,
      'esport' => l10n.upCategoryDescSport,
      'salut' => l10n.upCategoryDescHealth,
      'activa' => l10n.upCategoryDescActiva,
      'nutricio' => l10n.upCategoryDescNutrition,
      'descans' => l10n.upCategoryDescRest,
      _ => '',
    };

String upMoodLabel(AppLocalizations l10n, UpMood mood) => switch (mood) {
  UpMood.good => l10n.upMoodGood,
  UpMood.great => l10n.upMoodGreat,
  UpMood.sad => l10n.upMoodSad,
  UpMood.angry => l10n.upMoodAngry,
  UpMood.excited => l10n.upMoodExcited,
};

String upCountLabel(int count) => '$count ${count == 1 ? 'UP' : 'UPs'}';

/// Why a deleted UP cannot be restored, in the user's words.
String upRestoreBlockMessage(AppLocalizations l10n, UpRestoreBlock block) =>
    switch (block) {
      UpRestoreBlock.consentRevoked => l10n.upRestoreBlockedConsent,
      UpRestoreBlock.profileMigrating => l10n.upRestoreBlockedMigrating,
      UpRestoreBlock.awaitingAdultConsent => l10n.upRestoreBlockedAdultConsent,
      UpRestoreBlock.erasureRequested => l10n.upRestoreBlockedErasure,
    };
