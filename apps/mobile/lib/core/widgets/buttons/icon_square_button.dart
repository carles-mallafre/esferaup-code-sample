import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A 56dp outlined square icon button — the secondary actions (edit / share /
/// delete) in a detail-screen bottom bar, sitting beside a primary CTA.
class IconSquareButton extends StatelessWidget {
  const IconSquareButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: c.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.surfaceBorder),
              ),
              child: Icon(icon, size: 24, color: c.textStrong),
            ),
          ),
        ),
      ),
    );
  }
}
