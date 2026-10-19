import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// `C/SuccessBanner`: a soft success card — filled check chip + title + body on
/// a success-light surface. Used for the "Tu també tens una esfera" reassurance
/// on 08 Account Setup and other gentle confirmations.
class SuccessBanner extends StatelessWidget {
  const SuccessBanner({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.softSuccess,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c.successInk,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.check, size: 16, color: c.softSuccess),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.successInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.gray700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
