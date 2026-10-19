import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A large tappable navigation row: an optional rounded icon tile, a bold title,
/// an optional subtitle and a trailing chevron. Grows with its content (unlike
/// the fixed-height [IconRowCard]). Used for the Resums index, Configuració
/// sections and similar drill-down lists.
class NavListCard extends StatelessWidget {
  const NavListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBg,
    this.iconColor,
    this.trailing = const Icon(Icons.chevron_right_rounded),
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconBg;
  final Color? iconColor;
  final Widget? trailing;
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
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.surfaceBorder),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBg ?? c.secondaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 26, color: iconColor ?? c.secondary),
                ),
                const SizedBox(width: AppSpacing.s3),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: c.textStrong,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 15, color: c.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                IconTheme(
                  data: IconThemeData(color: c.gray400, size: 24),
                  child: trailing!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
