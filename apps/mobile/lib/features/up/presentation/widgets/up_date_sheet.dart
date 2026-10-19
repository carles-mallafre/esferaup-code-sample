import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/navigation/segmented_tabs.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<DateTime?> showUpDateSheet(BuildContext context, DateTime initial) {
  final now = DateTime.now();
  final today = DateUtils.dateOnly(now);
  final yesterday = today.subtract(const Duration(days: 1));
  var selected = DateUtils.dateOnly(initial);
  var mode = selected == today
      ? 0
      : selected == yesterday
      ? 1
      : 2;
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surfaceCard,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.upDateTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SegmentedTabs(
                labels: [
                  l10n.commonToday,
                  l10n.observationsGroupYesterday,
                  l10n.upDateCustom,
                ],
                selectedIndex: mode,
                onChanged: (value) => update(() {
                  mode = value;
                  if (value < 2) selected = value == 0 ? today : yesterday;
                }),
              ),
              if (mode == 2)
                CalendarDatePicker(
                  initialDate: selected,
                  firstDate: DateTime(2020),
                  lastDate: today,
                  onDateChanged: (value) => update(() => selected = value),
                ),
              const SizedBox(height: 20),
              AppButton(
                label: l10n.commonSave,
                onPressed: () => Navigator.pop(
                  context,
                  DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    now.hour,
                    now.minute,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
