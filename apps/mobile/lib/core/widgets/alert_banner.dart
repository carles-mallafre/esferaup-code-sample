import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

enum AlertTone { warning, error, info }

/// A tinted inline alert: a leading icon, a bold title, an optional detail line
/// and an optional chevron. Toned for warning / error / info. Used for the Arxiu
/// expiry banner and similar advisories.
class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = AlertTone.warning,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final AlertTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, border, ink) = switch (tone) {
      AlertTone.warning => (c.warningLight, c.warning, c.warningInk),
      AlertTone.error => (c.errorLight, c.error, c.errorInk),
      AlertTone.info => (c.primaryLight, c.primary, c.primary),
    };
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: ink),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 15, color: c.textStrong),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.s2),
                Icon(Icons.chevron_right_rounded, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
