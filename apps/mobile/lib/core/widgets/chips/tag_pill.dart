import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A static, soft grey tag pill (e.g. `Esport · Futbol`, `360° · CF Sant
/// Andreu`). Read-only metadata, distinct from the interactive [AppChip].
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            color: c.gray100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
