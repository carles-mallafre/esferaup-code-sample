import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/profile_pill.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The shared top bar for the main tabs (Esferes / Activa / 360°): the current
/// profile pill on the left and a notification bell (with unread badge) on the
/// right. An optional search action sits between them (used by Activa).
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.profileLabel,
    this.profileInitial = '·',
    this.profileAvatar,
    this.unread = 0,
    this.onProfile,
    this.onBell,
    this.onSearch,
    this.onMessages,
    this.messagesDot = false,
  });

  final String profileLabel;
  final String profileInitial;

  /// Replaces the pill's initial avatar (e.g. with the profile photo).
  final Widget? profileAvatar;
  final int unread;
  final VoidCallback? onProfile;
  final VoidCallback? onBell;
  final VoidCallback? onSearch;
  final VoidCallback? onMessages;

  /// Show a presence dot on the messages icon (unread conversations).
  final bool messagesDot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ProfilePill(
                  label: profileLabel,
                  initial: profileInitial,
                  avatar: profileAvatar,
                  onTap: onProfile,
                ),
              ),
            ),
            if (onSearch != null)
              _IconAction(
                icon: Icons.search_rounded,
                color: c.textStrong,
                onTap: onSearch,
                semanticLabel: l10n.activaCatalogSearchTooltip,
              ),
            if (onMessages != null)
              _IconAction(
                icon: Icons.chat_bubble_outline_rounded,
                color: c.textStrong,
                onTap: onMessages,
                dot: messagesDot,
                dotColor: c.success,
                semanticLabel: l10n.tabHeaderMessages,
              ),
            if (onBell != null)
              _IconAction(
                icon: Icons.notifications_none_rounded,
                color: c.textStrong,
                onTap: onBell,
                badge: unread,
                badgeColor: c.notifBadge,
                semanticLabel: l10n.notifTitle,
              ),
          ],
        ),
      ),
    );
  }
}

/// A tappable header icon with an optional unread badge.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.semanticLabel,
    this.onTap,
    this.badge = 0,
    this.badgeColor,
    this.dot = false,
    this.dotColor,
  });

  final IconData icon;
  final Color color;
  final String semanticLabel;
  final VoidCallback? onTap;
  final int badge;
  final Color? badgeColor;
  final bool dot;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final badgeBackground = badgeColor ?? c.notifBadge;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: semanticLabel,
      value: badge > 0 ? '$badge' : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 26, color: color),
                if (badge > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: badgeBackground.computeLuminance() > 0.179
                              ? c.pureBlack
                              : c.pureWhite,
                        ),
                      ),
                    ),
                  )
                else if (dot)
                  Positioned(
                    top: 7,
                    right: 8,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surfaceCanvas, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
