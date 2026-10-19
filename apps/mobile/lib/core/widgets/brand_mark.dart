import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The EsferaUp concentric "EsferaMark" brand symbol (`C/BrandMark/*`), drawn as
/// a crisp, theme-aware vector. Ratios are taken 1:1 from the Figma 168 dp mark:
/// outer 168 · middle 131 · inner 92 · centre 37. The Astra mark roles
/// keep the inner surface dark in dark mode. Empty states and
/// illustrations share these same rings rather than maintaining separate art.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 80,
    this.elevated = false,
    this.brandFixed = false,
    this.center,
    this.illuminated = false,
  });

  final double size;
  final Widget? center;
  final bool illuminated;

  /// Adds the soft lift-shadow used on the splash (§18.1).
  final bool elevated;

  /// Forces the mode-agnostic brand palette (outer + dot always `#145D9E`),
  /// for fixed-brand illustrations such as 06 First Point.
  final bool brandFixed;

  // Figma ratios off the 168 dp base.
  static const _cyanR = 131 / 168;
  static const _whiteR = 92 / 168;
  static const _dotR = 37 / 168;

  @override
  Widget build(BuildContext context) {
    final c = brandFixed ? AppColors.light : context.colors;
    final glow = illuminated && Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'EsferaUp',
      image: true,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: c.markMiddle.withValues(alpha: 0.22),
                    blurRadius: size * 0.22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        foregroundDecoration: glow
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.markMiddle.withValues(alpha: 0.55),
                  width: 1.25,
                ),
              )
            : null,
        child: _circle(
          size,
          c.markOuter,
          shadow: elevated,
          child: _circle(
            size * _cyanR,
            c.markMiddle,
            child: _circle(
              size * _whiteR,
              c.markInner,
              child: center ?? _circle(size * _dotR, c.markCentre),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circle(double d, Color color, {Widget? child, bool shadow = false}) {
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: d * 0.12,
                  spreadRadius: d * 0.01,
                  offset: Offset(0, d * 0.03),
                ),
              ]
            : null,
      ),
      child: child == null ? null : Center(child: child),
    );
  }
}
