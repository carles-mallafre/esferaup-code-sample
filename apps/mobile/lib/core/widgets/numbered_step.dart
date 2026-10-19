import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// One item in a plain numbered instruction list (`1. Mira la imatge…`). The
/// wrapped lines hang-indent under the text, not the number. Used for the
/// `Com es fa` steps on exercise detail and similar how-to lists.
class NumberedStep extends StatelessWidget {
  const NumberedStep({super.key, required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$number.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textStrong,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, height: 1.4, color: c.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}
