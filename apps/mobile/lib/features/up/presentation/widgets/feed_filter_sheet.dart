import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/features/feed/domain/entities/feed_filters.dart';
import 'package:esferaup/features/feed/presentation/providers/feed_providers.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedFilterSheet extends ConsumerStatefulWidget {
  const FeedFilterSheet({
    super.key,
    required this.profileId,
    required this.initial,
    this.query,
    this.kind = 'tot',
    this.fromDate,
    this.toDate,
  });
  final String profileId;
  final FeedFilters initial;
  final String? query;
  final String kind;
  final DateTime? fromDate, toDate;
  @override
  ConsumerState<FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends ConsumerState<FeedFilterSheet> {
  late FeedFilters _filters = widget.initial;
  late final _today = DateUtils.dateOnly(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    var from = widget.fromDate;
    if (_filters.days > 0) {
      final bound = DateTime(
        _today.year,
        _today.month,
        _today.day - _filters.days + 1,
      );
      if (from == null || from.isBefore(bound)) from = bound;
    }
    final count = ref
        .watch(
          profileFeedProvider(
            widget.profileId,
            query: widget.query,
            filters: _filters,
            filter: widget.kind,
            fromDate: from,
            toDate: widget.toDate,
          ),
        )
        .valueOrNull
        ?.matchingCount;
    Widget choices(
      String title,
      List<(String, String)> options,
      String selected,
      ValueChanged<String> pick,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.colors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (value, label) in options)
              AppChip(
                label: label,
                selected: selected == value,
                onTap: () => setState(() => pick(value)),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.feedFilters,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _filters = const FeedFilters()),
                  child: Text(l.feedClearFilters),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              l.feedCategories.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final category in const [
                  'casa',
                  'escola',
                  'emocions',
                  'esport',
                  'salut',
                  'activa',
                  'nutricio',
                  'descans',
                ])
                  AppChip(
                    label: upCategoryLabel(l, category),
                    selected: _filters.categories.split(',').contains(category),
                    onTap: () => setState(() {
                      final categories = _filters.categories
                          .split(',')
                          .where((s) => s.isNotEmpty)
                          .toSet();
                      if (!categories.remove(category)) {
                        categories.add(category);
                      }
                      _filters = _filters.copyWith(
                        categories: (categories.toList()..sort()).join(','),
                      );
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            choices(
              l.feedMedia,
              [
                ('all', l.myUpsFilterAll),
                ('photo', l.addUpPhoto),
                ('note', l.feedNote),
                ('audio', l.addUpAudio),
              ],
              _filters.media,
              (v) => _filters = _filters.copyWith(media: v),
            ),
            choices(
              l.feedOrigin,
              [
                ('all', l.myUpsFilterAll),
                ('family', l.feedFamily),
                ('centre', l.feedCentre),
                ('completed', l.feedCompleted),
              ],
              _filters.origin,
              (v) => _filters = _filters.copyWith(origin: v),
            ),
            choices(
              l.feedPeriod,
              [
                ('0', l.myUpsPeriodAlways),
                ('7', l.myUpsPeriodWeek),
                ('30', l.myUpsPeriodMonth),
                ('90', l.feedThreeMonths),
                ('365', l.feedYear),
              ],
              '${_filters.days}',
              (v) => _filters = _filters.copyWith(days: int.parse(v)),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push(Routes.patrons);
              },
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l.feedPatterns),
            ),
            AppButton(
              label: count == null
                  ? l.feedApplyFilters
                  : '${l.feedApplyFilters} · ${l.feedResults(count)}',
              onPressed: () => Navigator.pop(context, _filters),
            ),
          ],
        ),
      ),
    );
  }
}
