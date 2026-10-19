import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A soft informational card — muted surface, a leading glyph, a SemiBold title
/// and a body line. Used for the "Per què afegir-los?" explainer on 10 Add
/// Children and similar reassurance panels.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.leading,
    required this.title,
    required this.body,
  });

  final Widget leading;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceBorderSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, height: 28, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: c.gray700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
