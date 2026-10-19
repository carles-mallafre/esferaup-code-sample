import 'package:esferaup/core/theme/app_action_colors.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Mirrors the Figma `C/Btn-*` masters: full-width, height 56 (small 44),
/// radius 18 (small 14), label 16 Bold. Variants are token-driven so both
/// modes are correct. One widget replaces the Light/Dark master pairs.
enum AppButtonVariant { primary, secondary, ghost, danger, primaryInverse }

enum AppButtonSize { normal, small }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.normal,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;

  static const double _hNormal = 56;
  static const double _hSmall = 44;
  static const double _rNormal = 18;
  static const double _rSmall = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isSmall = size == AppButtonSize.small;
    final height = isSmall ? _hSmall : _hNormal;
    final radius = BorderRadius.circular(isSmall ? _rSmall : _rNormal);
    final disabled = onPressed == null || loading;

    final (bg, fg, border) = switch (variant) {
      AppButtonVariant.primary => (c.primary, c.actionLabel, null),
      AppButtonVariant.primaryInverse => (c.surfaceCard, c.primary, null),
      AppButtonVariant.secondary => (
        c.surfaceCard,
        c.textStrong,
        c.surfaceBorder,
      ),
      AppButtonVariant.ghost => (Colors.transparent, c.textLink, null),
      AppButtonVariant.danger => (
        AppActionColors.dangerBackground,
        AppActionColors.dangerForeground,
        null,
      ),
    };

    final label = Text(
      this.label,
      style: TextStyle(
        fontSize: isSmall ? 14 : 16,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    );

    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: !disabled,
        label: this.label,
        onTap: disabled ? null : onPressed,
        child: Material(
          color: bg,
          borderRadius: radius,
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: radius,
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              width: fullWidth ? double.infinity : null,
              padding: EdgeInsets.symmetric(
                horizontal: fullWidth ? AppSpacing.s4 : AppSpacing.s6,
                vertical: isSmall ? 10 : 14,
              ),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: border == null ? null : Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: fg,
                      ),
                    )
                  else ...[
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: fg),
                      const SizedBox(width: AppSpacing.s2),
                    ],
                    Flexible(child: label),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: AppSpacing.s2),
                      Icon(trailingIcon, size: 20, color: fg),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
