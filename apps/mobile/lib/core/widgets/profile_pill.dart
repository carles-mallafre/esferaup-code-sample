import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// `C/ProfilePill/Header`: a compact profile selector — avatar, name, and a
/// dropdown caret on a primary-light pill. Tapping opens the profile switcher.
/// Used on Add UP and other "acting as this profile" headers.
class ProfilePill extends StatelessWidget {
  const ProfilePill({
    super.key,
    required this.label,
    this.initial = '·',
    this.avatar,
    this.onTap,
  });

  final String label;
  final String initial;

  /// Replaces the initial avatar (e.g. with the profile photo) when given.
  final Widget? avatar;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      enabled: enabled,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: c.primaryLight,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar ??
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: c.avatarPeach,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.avatarInk,
                      ),
                    ),
                  ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: c.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
