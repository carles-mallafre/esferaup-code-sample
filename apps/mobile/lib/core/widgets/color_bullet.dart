import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A bullet-list item with a coloured status dot and multi-line text. The dot
/// colour signals tone (e.g. green = gain, red = loss). Used on the
/// Migració-at-18 "what changes" list and similar explainer lists.
class ColorBullet extends StatelessWidget {
  const ColorBullet({super.key, required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 17, height: 1.4, color: c.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}
