import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A card with a filled check disc and a line of text — a positive/affirmation
/// list item ("el que ha anat bé", "a tenir en compte"). [tone] colours the
/// disc.
class CheckItemCard extends StatelessWidget {
  const CheckItemCard({super.key, required this.text, this.color, this.onTap});

  final String text;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.surfaceBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color ?? c.success,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 20,
                  color:
                      ThemeData.estimateBrightnessForColor(
                            color ?? c.success,
                          ) ==
                          Brightness.dark
                      ? c.textOnDark
                      : c.textOnLight,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: c.textStrong,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
