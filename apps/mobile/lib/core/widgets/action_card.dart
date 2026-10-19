import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// `C/ActionCard/*`: a 72 dp tappable row — a filled primary icon chip, a title
/// + helper, and a chevron, on a soft-shadowed surface card. Used for the next
/// actions on N2 Profile Created (share / add / connect).
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      enabled: enabled,
      child: Material(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              color: c.surfaceCard,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.iconSurface,
                  ),
                  child: Icon(icon, size: 21, color: c.iconForeground),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 16, color: c.gray400),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
