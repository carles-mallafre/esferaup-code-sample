import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A plan's pricing pill in the Activa catalogue. Four soft variants — free
/// (green), premium (blue), mixed (amber, `Premium + N €`) and paid (grey,
/// `N €`) — each carrying a caller-supplied [label]. Sibling of the simpler
/// [TierBadge] used on category cards.
enum PlanPrice { free, premium, mixed, paid }

class PlanPriceBadge extends StatelessWidget {
  const PlanPriceBadge({super.key, required this.price, required this.label});

  final PlanPrice price;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (price) {
      PlanPrice.free => (c.softSuccess, c.successInk),
      PlanPrice.premium => (c.primaryLight, c.primary),
      PlanPrice.mixed => (c.warningLight, c.warningInk),
      PlanPrice.paid => (c.pillPaidBg, c.textStrong),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
