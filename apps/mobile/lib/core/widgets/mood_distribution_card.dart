import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One slice of a [MoodDistributionCard].
class DistributionSlice {
  const DistributionSlice({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
}

/// A horizontal stacked bar (segments sized by value) with a labelled legend
/// below, in a card. Used for the mood / "com ha estat" breakdown on resum
/// detail screens.
class MoodDistributionCard extends StatelessWidget {
  const MoodDistributionCard({super.key, required this.slices});

  final List<DistributionSlice> slices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = slices.where((s) => s.value > 0).toList();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    flex: shown[i].value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: shown[i].color,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s2,
            children: [
              for (final s in shown)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${s.label} ${s.value}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textStrong,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
