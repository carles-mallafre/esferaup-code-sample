import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Plan/content status badge mirroring `C/StatusPill/*`: h25, radius 12, 10×5
/// padding, label 12 SemiBold. Variants map to design tokens.
enum StatusPillVariant { free, paid, mixed, premium }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.variant});

  final String label;
  final StatusPillVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (variant) {
      StatusPillVariant.premium => (c.primaryLight, c.primary),
      StatusPillVariant.paid => (c.pillPaidBg, c.textStrong),
      StatusPillVariant.mixed => (c.warningLight, c.warningInk),
      StatusPillVariant.free => (c.softSuccess, c.successInk),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 25),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
