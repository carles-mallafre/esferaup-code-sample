import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One column in a [StatsRowCard].
class StatItem {
  const StatItem({
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });
  final String value;
  final String label;

  /// Override the value colour (e.g. green for a positive count).
  final Color? color;

  /// Makes the column a button that drills into the stat.
  final VoidCallback? onTap;
}

/// A summary card of 2–4 stats laid out in equal columns with hairline
/// dividers: a big value over a muted label. Used on the 360° tab header and
/// other dashboards.
class StatsRowCard extends StatelessWidget {
  const StatsRowCard({super.key, required this.items});

  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cells = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        cells.add(Container(width: 1, height: 36, color: c.gray200));
      }
      final it = items[i];
      cells.add(Expanded(child: _cell(c, it)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.s4,
        horizontal: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: cells,
      ),
    );
  }

  Widget _cell(AppColors c, StatItem it) {
    final column = Column(
      children: [
        Text(
          it.value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: it.color ?? c.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          it.label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
      ],
    );
    if (it.onTap == null) return column;
    return Semantics(
      button: true,
      label: '${it.value} ${it.label}',
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: it.onTap,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(child: column),
            ),
          ),
        ),
      ),
    );
  }
}
