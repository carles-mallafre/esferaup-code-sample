import 'package:esferaup/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enlarged = MediaQuery.textScalerOf(context).scale(14) > 20;
    Widget segment(int index) {
      final text = Text(
        labels[index],
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: index == selectedIndex ? c.actionLabel : c.textMuted,
        ),
      );
      return Semantics(
        button: true,
        selected: index == selectedIndex,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          onTap: () => onChanged(index),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AnimatedContainer(
              constraints: const BoxConstraints(minHeight: 36),
              padding: EdgeInsets.symmetric(
                horizontal: enlarged ? 16 : 8,
                vertical: 6,
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == selectedIndex ? c.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: enlarged
                  ? text
                  : FittedBox(fit: BoxFit.scaleDown, child: text),
            ),
          ),
        ),
      );
    }

    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            if (enlarged) segment(i) else Expanded(child: segment(i)),
        ],
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(22),
      ),
      child: enlarged
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
          : row,
    );
  }
}
