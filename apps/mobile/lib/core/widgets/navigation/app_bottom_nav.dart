import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// `C/BottomNav/*` — the 4-tab bar (Inici / Activa / Esferes / 360°). Surface
/// card fill + a 1 dp `gray/200` top stroke (consistent Light + Dark); active
/// tab = primary, inactive = `gray/500`; 11px labels. The FAB-UP floats above
/// it (rendered by the shell scaffold).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    // "360°" stays untranslated per the glossary; the other labels follow the locale.
    final tabs = [
      (icon: Icons.home_outlined, active: Icons.home, label: l10n.navInici),
      (
        icon: Icons.school_outlined,
        active: Icons.school,
        label: l10n.navActiva,
      ),
      (
        icon: Icons.adjust_outlined,
        active: Icons.adjust,
        label: l10n.navEsferes,
      ),
      (icon: Icons.hub_outlined, active: Icons.hub, label: l10n.nav360),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceCard,
        border: Border(top: BorderSide(color: c.gray200)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _Tab(
                      tab: tabs[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final ({IconData icon, IconData active, String label}) tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.primary : c.gray500;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      // The label is painted by the Text below; without this a reader hears
      // "Inici, Inici, selected, button" on every tab.
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? tab.active : tab.icon, size: 26, color: color),
              const SizedBox(height: 4),
              Text(
                tab.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
