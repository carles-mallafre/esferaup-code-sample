import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The pinned bottom action area used across the setup flow: a hairline top
/// divider over the canvas colour, safe-area inset, and 16/20 padding. Holds the
/// primary CTA (and any secondary text link) passed as [child].
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceCanvas,
        border: Border(top: BorderSide(color: c.gray200)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s5,
            AppSpacing.s4,
            AppSpacing.s5,
          ),
          child: child,
        ),
      ),
    );
  }
}
