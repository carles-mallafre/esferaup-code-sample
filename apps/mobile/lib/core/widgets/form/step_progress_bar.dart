import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The 8 dp rounded progress track on the multi-step setup flow (§18.3 Pas N
/// de M). [value] is 0–1; the filled portion animates so step changes glide.
class StepProgressBar extends StatelessWidget {
  const StepProgressBar({super.key, required this.value});

  /// Fraction filled, 0–1 (e.g. 0.5 for "Pas 1 de 2").
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: c.gray200),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              widthFactor: value.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
