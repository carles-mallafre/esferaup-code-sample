import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Filter chip mirroring `C/Chip/Default` + `C/Chip/Selected`: radius 18,
/// 36 pt pill with 14 pt side padding, label 13 (Medium default / SemiBold selected). Default carries
/// a 1px border + card fill; Selected is filled with the primary colour.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.horizontalPadding = 14,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(18);
    // The tap target stays 44 pt tall; the visible pill is 36 pt and centred
    // in it, so rows of chips don't look oversized.
    return Semantics(
      label: label,
      excludeSemantics: true,
      button: onTap != null,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Material(
              color: selected ? c.primary : c.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: selected
                    ? BorderSide.none
                    : BorderSide(color: c.surfaceBorder),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        label,
                        textHeightBehavior: const TextHeightBehavior(
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected ? c.actionLabel : c.textStrong,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
