import 'dart:math' as math;
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/features/feed/domain/entities/feed_entities.dart';
import 'package:esferaup/features/feed/presentation/providers/feed_providers.dart';
import 'package:esferaup/features/feed/presentation/widgets/feed_skeletons.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

DateTime upWeekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + 1);
String upMonthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

class UpTimeline extends ConsumerWidget {
  const UpTimeline({
    super.key,
    required this.profileId,
    required this.period,
    required this.date,
    required this.onDate,
    required this.onDay,
    required this.itemBuilder,
  });
  final String profileId;
  final int period; // 0 day, 1 week, 2 month
  final DateTime date;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<DateTime> onDay;
  final Widget Function(FeedItem) itemBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = period == 2
        ? DateTime(date.year, date.month)
        : upWeekStart(date);
    final end = period == 2
        ? DateTime(date.year, date.month + 1, 0)
        : DateTime(start.year, start.month, start.day + 6);
    final first = ref.watch(
      historicMonthProvider(profileId, upMonthKey(start)),
    );
    final last = upMonthKey(start) == upMonthKey(end)
        ? first
        : ref.watch(historicMonthProvider(profileId, upMonthKey(end)));
    final l = AppLocalizations.of(context);
    Widget content;
    if (first.isLoading || last.isLoading) {
      content = const FeedRowsSkeleton();
    } else if (first.hasError || last.hasError) {
      content = Column(
        children: [
          Text(l.feedLoadError),
          AppButton(
            label: l.commonRetry,
            onPressed: () {
              for (final key in {upMonthKey(start), upMonthKey(end)}) {
                ref
                    .read(historicMonthCacheProvider.notifier)
                    .evict(profileId, key);
                ref.invalidate(historicMonthProvider(profileId, key));
              }
            },
          ),
        ],
      );
    } else {
      final days = {
        ...{
          for (final d in first.requireValue.days)
            DateUtils.dateOnly(d.date): d.ups,
        },
        ...{
          for (final d in last.requireValue.days)
            DateUtils.dateOnly(d.date): d.ups,
        },
      };
      final selected = days[DateUtils.dateOnly(date)] ?? <FeedItem>[];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (period == 0) ...[
            _WeekStrip(start: start, selected: date, days: days, onDay: onDay),
            const SizedBox(height: 24),
            Text(
              DateFormat.yMMMMEEEEd(l.localeName).format(date),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _DayOverview(items: selected),
            const SizedBox(height: 16),
            if (selected.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.myUpsEmpty, textAlign: TextAlign.center),
              ),
            for (final item in selected)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: itemBuilder(item),
              ),
          ] else if (period == 1) ...[
            _WeekOverview(
              days: [
                for (var i = 0; i < 7; i++)
                  days[DateTime(start.year, start.month, start.day + i)] ?? [],
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DayRow(
                  date: DateTime(start.year, start.month, start.day + i),
                  items:
                      days[DateTime(start.year, start.month, start.day + i)] ??
                      [],
                  onTap: () =>
                      onDay(DateTime(start.year, start.month, start.day + i)),
                ),
              ),
          ] else ...[
            _MonthGrid(
              month: start,
              selected: date,
              days: days,
              onDate: onDate,
            ),
            const SizedBox(height: 16),
            _DayRow(date: date, items: selected, onTap: () => onDay(date)),
          ],
        ],
      );
    }
    final previous = period == 2
        ? DateTime(date.year, date.month - 1, 1)
        : DateTime(date.year, date.month, date.day - 7);
    final next = period == 2
        ? DateTime(date.year, date.month + 1, 1)
        : DateTime(date.year, date.month, date.day + 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.summaryPreviousPeriod,
              onPressed: () => onDate(previous),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                period == 2
                    ? DateFormat.yMMMM(l.localeName).format(date)
                    : '${DateFormat.MMMd(l.localeName).format(start)} – ${DateFormat.MMMd(l.localeName).format(end)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: l.summaryNextPeriod,
              onPressed:
                  (period == 2 ? next : upWeekStart(next)).isAfter(
                    DateTime.now(),
                  )
                  ? null
                  : () => onDate(next),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.start,
    required this.selected,
    required this.days,
    required this.onDay,
  });
  final DateTime start, selected;
  final Map<DateTime, List<FeedItem>> days;
  final ValueChanged<DateTime> onDay;
  @override
  Widget build(BuildContext context) => _SevenColumns(
    children: [
      for (var i = 0; i < 7; i++)
        _DateCell(
          date: DateTime(start.year, start.month, start.day + i),
          selected: selected,
          items: days[DateTime(start.year, start.month, start.day + i)] ?? [],
          onTap: () => onDay(DateTime(start.year, start.month, start.day + i)),
          weekday: true,
        ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.days,
    required this.onDate,
  });
  final DateTime month, selected;
  final Map<DateTime, List<FeedItem>> days;
  final ValueChanged<DateTime> onDate;
  @override
  Widget build(BuildContext context) {
    final length = DateTime(month.year, month.month + 1, 0).day;
    final offset = month.weekday - 1;
    final locale = AppLocalizations.of(context).localeName;
    return _SevenColumns(
      children: [
        for (var i = 0; i < 7; i++)
          Center(
            child: Text(
              DateFormat.E(locale).format(DateTime(2026, 6, 1 + i)),
              style: TextStyle(fontSize: 11, color: context.colors.textMuted),
            ),
          ),
        for (var i = 0; i < ((length + offset + 6) ~/ 7) * 7; i++)
          if (i < offset || i >= length + offset)
            const SizedBox(height: 64)
          else
            _DateCell(
              date: DateTime(month.year, month.month, i - offset + 1),
              selected: selected,
              items:
                  days[DateTime(month.year, month.month, i - offset + 1)] ?? [],
              onTap: () =>
                  onDate(DateTime(month.year, month.month, i - offset + 1)),
            ),
      ],
    );
  }
}

class _SevenColumns extends StatelessWidget {
  const _SevenColumns({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minCell = MediaQuery.textScalerOf(context).scale(16) > 24
          ? 76.0
          : 44.0;
      final width = math.max(constraints.maxWidth, minCell * 7);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Table(
            children: [
              for (var row = 0; row < children.length / 7; row++)
                TableRow(children: children.sublist(row * 7, row * 7 + 7)),
            ],
          ),
        ),
      );
    },
  );
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.selected,
    required this.items,
    required this.onTap,
    this.weekday = false,
  });
  final DateTime date, selected;
  final List<FeedItem> items;
  final VoidCallback onTap;
  final bool weekday;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = DateUtils.isSameDay(date, selected);
    final l = AppLocalizations.of(context);
    final enabled = !date.isAfter(DateTime.now());
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: active,
        enabled: enabled,
        label:
            '${MaterialLocalizations.of(context).formatFullDate(date)} · ${upCountLabel(items.length)}',
        onTap: enabled ? onTap : null,
        excludeSemantics: true,
        child: Material(
          color: weekday
              ? active
                    ? c.primary
                    : c.surfaceCard
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  if (weekday)
                    Text(
                      DateFormat.E(l.localeName).format(date),
                      style: TextStyle(
                        fontSize: 10,
                        color: active ? c.actionLabel : c.textMuted,
                      ),
                    ),
                  Container(
                    padding: weekday
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !weekday && active
                          ? c.primary
                          : Colors.transparent,
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: active
                            ? c.actionLabel
                            : enabled
                            ? c.textStrong
                            : c.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < math.min(items.length, 3); i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active && weekday
                                ? c.actionLabel
                                : items.any((e) => e.isCrisi)
                                ? c.error
                                : c.success,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.date, required this.items, required this.onTap});
  final DateTime date;
  final List<FeedItem> items;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = !date.isAfter(DateTime.now());
    return Semantics(
      key: ValueKey(
        'timeline-day-${DateUtils.dateOnly(date).toIso8601String()}',
      ),
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      label:
          '${MaterialLocalizations.of(context).formatFullDate(date)} · ${upCountLabel(items.length)} · ${l.feedCrisesCount(items.where((e) => e.isCrisi).length)}',
      onTap: enabled ? onTap : null,
      child: _Panel(
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  children: [
                    Text(
                      DateFormat.E(l.localeName).format(date),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${date.day}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upCountLabel(items.length),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _MoodBar(items: items),
                    if (items.any((e) => e.isCrisi))
                      Text(
                        l.feedCrisesCount(items.where((e) => e.isCrisi).length),
                        style: TextStyle(color: context.colors.error),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayOverview extends StatelessWidget {
  const _DayOverview({required this.items});
  final List<FeedItem> items;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${upCountLabel(items.length)} · ${l.feedCrisesCount(items.where((e) => e.isCrisi).length)}',
          ),
          const SizedBox(height: 12),
          Text(
            l.feedDayOverview,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mood in UpMood.values)
                Semantics(
                  excludeSemantics: true,
                  label:
                      '${upMoodLabel(l, mood)}: ${items.where((e) => e.mood == mood).length}',
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: mood.color.withValues(alpha: .22),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${items.where((e) => e.mood == mood).length}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekOverview extends StatelessWidget {
  const _WeekOverview({required this.days});
  final List<List<FeedItem>> days;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = days.expand((d) => d).toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.feedWeekOverview,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Text(upCountLabel(items.length)),
              Text(l.feedDaysCount(days.where((d) => d.isNotEmpty).length)),
              Text(l.feedCrisesCount(items.where((e) => e.isCrisi).length)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodBar extends StatelessWidget {
  const _MoodBar({required this.items});
  final List<FeedItem> items;
  @override
  Widget build(BuildContext context) {
    final withMood = items.where((e) => e.mood != null).toList();
    if (withMood.isEmpty) {
      return Text(
        AppLocalizations.of(context).feedNoMood,
        style: TextStyle(fontSize: 12, color: context.colors.textMuted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            for (final mood in UpMood.values)
              if (withMood.any((e) => e.mood == mood))
                Expanded(
                  flex: withMood.where((e) => e.mood == mood).length,
                  child: ColoredBox(
                    color: mood.color,
                    child: const SizedBox.expand(),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.surfaceBorder),
    ),
    child: child,
  );
}
