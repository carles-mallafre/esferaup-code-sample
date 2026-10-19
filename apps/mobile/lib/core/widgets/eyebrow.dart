import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Small uppercase section label mirroring `C/Eyebrow` / `C/Text/SectionEyebrow`:
/// 11px SemiBold, tracked, muted by default.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: color ?? context.colors.textMuted,
      ),
    );
  }
}
