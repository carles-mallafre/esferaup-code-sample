import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// A grouped settings card: stacks [SettingsRow]s inside one rounded surface
/// with hairline dividers between them (inset past the leading icon).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.rows, this.dividerIndent = 56});

  final List<Widget> rows;

  /// Where the hairline starts: past the icon tile by default.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: dividerIndent,
            color: c.surfaceBorder,
          ),
        );
      }
      children.add(rows[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(children: children),
    );
  }
}
