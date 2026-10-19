import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A single row inside a [SettingsGroup]: a small icon tile, a title, an
/// optional subtitle OR a trailing value, and a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
    return Semantics(
      container: true,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.secondaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 20, color: iconColor ?? c.primary),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textStrong,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(fontSize: 13, color: c.textMuted),
                          ),
                        ],
                        if (value != null && largeText) ...[
                          const SizedBox(height: 2),
                          Text(
                            value!,
                            style: TextStyle(fontSize: 13, color: c.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (value != null && !largeText) ...[
                    const SizedBox(width: AppSpacing.s2),
                    // A long value gives way to the title, never the reverse.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth / 2,
                      ),
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: c.textMuted),
                      ),
                    ),
                  ],
                  // Rows without an action keep the chevron's slot so values line up.
                  const SizedBox(width: 4),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: c.textStrong,
                    )
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
