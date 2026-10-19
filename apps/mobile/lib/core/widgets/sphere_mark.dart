import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A concentric "esfera" bubble in a single [color] — the EsferaMark rendered per
/// life-dimension. Used on the Esferes grid (sized by UP count) and esfera detail
/// headers. Ratios mirror the brand mark (1 · 0.78 · 0.55 · 0.22).
class SphereMark extends StatelessWidget {
  const SphereMark({super.key, required this.color, this.size = 120});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _ring(
      size,
      color.withValues(alpha: 0.2),
      child: _ring(
        size * 0.78,
        color.withValues(alpha: 0.4),
        child: _ring(
          size * 0.55,
          context.colors.markInner,
          child: _ring(size * 0.26, color),
        ),
      ),
    );
  }

  Widget _ring(double d, Color c, {Widget? child}) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    child: child == null ? null : Center(child: child),
  );
}
