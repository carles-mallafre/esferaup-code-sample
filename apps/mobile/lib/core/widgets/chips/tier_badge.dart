import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Content-tier marker for Activa (`Gratis` / `Premium`). A soft pill — green
/// for free content, primary-light for premium — shown on category and exercise
/// cards. Distinct from [StatusPill], which marks a *plan's* pricing on dark
/// plan headers.
enum ContentTier { free, premium }

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier});

  final ContentTier tier;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final (bg, fg, label) = switch (tier) {
      ContentTier.free => (c.softSuccess, c.successInk, l10n.activaCatalogFree),
      ContentTier.premium => (
        c.primaryLight,
        c.primary,
        l10n.subscriptionPremium,
      ),
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
