import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The "Com et sents?" mood row (§6 Add UP): five 56 dp face circles. Selected =
/// primary-light fill + primary ring; unselected = surface + border. Reusable
/// wherever a mood is captured (Add UP, future quick-log).
class MoodSelector extends StatelessWidget {
  const MoodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.labelBuilder,
  });

  final UpMood? selected;
  final ValueChanged<UpMood> onChanged;

  /// Words shown (and announced) under each face; the mood names by default.
  final String Function(UpMood mood)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mood in UpMood.values)
          Expanded(
            child: _MoodItem(
              mood: mood,
              label: labelBuilder?.call(mood) ?? upMoodLabel(l10n, mood),
              isSelected: mood == selected,
              onTap: () => onChanged(mood),
              colors: c,
            ),
          ),
      ],
    );
  }
}

class _MoodItem extends StatelessWidget {
  const _MoodItem({
    required this.mood,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  final UpMood mood;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colors.primaryLight : colors.surfaceCard,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.gray200,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Icon(mood.icon, size: 32, color: mood.color),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? colors.primary : colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
