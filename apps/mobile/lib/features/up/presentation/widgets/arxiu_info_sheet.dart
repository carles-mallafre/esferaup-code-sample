import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Figma "Add UP · Arxiu info" (1436:36113): what the family archive is and
/// which documents belong there. Informational only; it never flips the
/// "També desa al meu Arxiu" checkbox.
Future<void> showArxiuInfoSheet(BuildContext context) {
  final c = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surfaceCard,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      final examples = [
        (Icons.favorite_border, l10n.arxiuSectionHealth, l10n.arxiuInfoHealth),
        (Icons.school_outlined, l10n.arxiuSectionSchool, l10n.arxiuInfoSchool),
        (
          Icons.badge_outlined,
          l10n.arxiuSectionIdentity,
          l10n.arxiuInfoIdentity,
        ),
        (
          Icons.shield_outlined,
          l10n.arxiuSectionInsurance,
          l10n.arxiuInfoInsurance,
        ),
      ];
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s5,
            0,
            AppSpacing.s5,
            AppSpacing.s4,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.arxiuInfoTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textStrong,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.arxiuInfoBody,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.arxiuInfoExamples,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                for (final (icon, title, hint) in examples)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s2,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: c.primary, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: c.textStrong,
                                ),
                              ),
                              Text(
                                hint,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.s4),
                AppButton(
                  label: l10n.arxiuInfoGotIt,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
