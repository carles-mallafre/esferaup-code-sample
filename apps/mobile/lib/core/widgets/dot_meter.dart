import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A small "N of M" activity meter — [filled] solid dots followed by empty
/// dots. Used on 360° place cards to show recent observation activity.
class DotMeter extends StatelessWidget {
  const DotMeter({
    super.key,
    required this.filled,
    this.total = 5,
    this.color,
    this.size = 7,
  });

  final int filled;
  final int total;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? (color ?? c.success) : c.gray300,
            ),
          ),
        ],
      ],
    );
  }
}
