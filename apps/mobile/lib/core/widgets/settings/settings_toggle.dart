import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A settings switch with its own card: title, one line of consequence, toggle.
///
/// Above ~150% text the switch moves below the text instead of beside it. A
/// `SwitchListTile` keeps the control on its trailing edge at every size, which
/// at 200% leaves the heading a sliver of width and breaks it mid-word.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.backgroundColor,
    this.activeColor,
    this.titleColor,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? backgroundColor;
  final Color? activeColor;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleWidget = Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: titleColor ?? c.textStrong,
      ),
    );
    final subtitleWidget = Text(
      subtitle,
      style: TextStyle(fontSize: 12, color: subtitleColor ?? c.textMuted),
    );
    final large = MediaQuery.textScalerOf(context).scale(14) >= 21;
    return Material(
      color: backgroundColor ?? c.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: large
          ? Semantics(
              container: true,
              excludeSemantics: true,
              toggled: value,
              enabled: onChanged != null,
              label: '$title, $subtitle',
              onTap: onChanged == null ? null : () => onChanged!(!value),
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(!value),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleWidget,
                      const SizedBox(height: 4),
                      subtitleWidget,
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Switch.adaptive(
                          value: value,
                          onChanged: onChanged,
                          activeTrackColor: activeColor ?? c.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: titleWidget,
              subtitle: subtitleWidget,
              value: value,
              activeTrackColor: activeColor ?? c.primary,
              onChanged: onChanged,
            ),
    );
  }
}
