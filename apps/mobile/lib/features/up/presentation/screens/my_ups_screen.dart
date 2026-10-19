import 'dart:async';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/router/app_router.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/category_colors.dart';
import 'package:esferaup/core/widgets/alert_banner.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/content_author_line.dart';
import 'package:esferaup/core/widgets/buttons/icon_square_button.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/core/widgets/inputs/app_text_field.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/core/widgets/navigation/segmented_tabs.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/feed/domain/entities/feed_entities.dart';
import 'package:esferaup/features/feed/domain/entities/feed_filters.dart';
import 'package:esferaup/features/feed/presentation/providers/feed_providers.dart';
import 'package:esferaup/features/feed/presentation/widgets/feed_skeletons.dart';
import 'package:esferaup/features/professional_sharing/presentation/providers/professional_sharing_providers.dart';
import 'package:esferaup/features/threesixty/presentation/providers/threesixty_providers.dart';
import 'package:esferaup/features/threesixty/presentation/widgets/observation_detail_sheet.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/widgets/feed_filter_sheet.dart';
import 'package:esferaup/features/up/presentation/widgets/up_feed_card.dart';
import 'package:esferaup/features/up/presentation/widgets/up_timeline.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class MyUpsScreen extends ConsumerStatefulWidget {
  const MyUpsScreen({
    super.key,
    this.onBack,
    this.onOpenUp,
    this.onOpenDocument,
    this.embedded = false,
  });
  final VoidCallback? onBack;
  final bool embedded;
  final ValueChanged<FeedItem>? onOpenUp;
  final ValueChanged<String>? onOpenDocument;
  @override
  ConsumerState<MyUpsScreen> createState() => _MyUpsScreenState();
}

class _MyUpsScreenState extends ConsumerState<MyUpsScreen> {
  int _type = 0;
  int _period = 3;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  FeedFilters _filters = const FeedFilters();
  String? _query;
  Timer? _debounce;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  ProfileFeedProvider? _loadingPage;
  bool get _hasFilters => _query != null || !_filters.isEmpty || _type != 0;
  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _query = null;
      _filters = const FeedFilters();
      _type = 0;
    });
  }

  void _changePeriod(int period, {DateTime? date}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _period = period;
      if (date != null) _date = date;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  DateTime _adjacentPeriod(int direction) => _period == 2
      ? DateTime(_date.year, _date.month + direction)
      : DateTime(
          _date.year,
          _date.month,
          _date.day + direction * (_period == 1 ? 7 : 1),
        );
  bool get _timeline =>
      _period < 3 && _filters.isEmpty && _query == null && _type == 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_timeline &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 240) {
      _loadMore();
    }
  }

  void _setDate(DateTime date) => setState(
    () => _date = date.isAfter(DateTime.now())
        ? DateUtils.dateOnly(DateTime.now())
        : date,
  );
  void _setQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        setState(() => _query = value.trim().isEmpty ? null : value.trim());
      }
    });
  }

  ProfileFeedProvider _provider(
    String profileId, {
    bool ignoreAdvanced = false,
  }) {
    DateTime? from, to;
    if (_period == 0) {
      from = _date;
      to = DateTime(
        _date.year,
        _date.month,
        _date.day + 1,
      ).subtract(const Duration(microseconds: 1));
    }
    if (_period == 1) {
      from = upWeekStart(_date);
      to = DateTime(
        from.year,
        from.month,
        from.day + 7,
      ).subtract(const Duration(microseconds: 1));
    }
    if (_period == 2) {
      from = DateTime(_date.year, _date.month);
      to = DateTime(
        _date.year,
        _date.month + 1,
      ).subtract(const Duration(microseconds: 1));
    }
    if (!ignoreAdvanced && _filters.days > 0) {
      final now = DateTime.now();
      final bound = DateTime(now.year, now.month, now.day - _filters.days + 1);
      if (from == null || from.isBefore(bound)) from = bound;
    }
    return profileFeedProvider(
      profileId,
      filter: const ['tot', 'ups', 'arxius', 'crisis'][_type],
      query: _query,
      filters: _filters,
      fromDate: from,
      toDate: to,
    );
  }

  Future<void> _loadMore() async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    final provider = _provider(profile.id);
    if (_loadingPage == provider) return;
    setState(() => _loadingPage = provider);
    try {
      await ref.read(provider.notifier).loadMore();
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, AppLocalizations.of(context).feedLoadError);
      }
    } finally {
      if (mounted && _loadingPage == provider) {
        setState(() => _loadingPage = null);
      }
    }
  }

  Future<void> _openFilters(String profileId) async {
    FocusScope.of(context).unfocus();
    final base = _provider(profileId, ignoreAdvanced: true);
    final result = await showModalBottomSheet<FeedFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.colors.surfaceCard,
      builder: (_) => FeedFilterSheet(
        profileId: profileId,
        initial: _filters,
        query: _query,
        kind: base.filter,
        fromDate: base.fromDate,
        toDate: base.toDate,
      ),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  Future<void> _openObservation(String profileId, String id) async {
    try {
      final entries = await ref.read(
        allPlaceObservationsProvider(profileId).future,
      );
      final entry = entries.where((e) => e.observation.id == id).firstOrNull;
      if (!mounted) return;
      if (entry == null) {
        showErrorSnackBar(context, AppLocalizations.of(context).feedLoadError);
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ObservationDetailSheet(
          profileId: profileId,
          place: entry.place,
          observation: entry.observation,
          permission: entry.place.permissionFor(entry.observation.category),
        ),
      );
      if (mounted) ref.invalidate(allPlaceObservationsProvider(profileId));
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(context, AppLocalizations.of(context).feedLoadError);
      }
    }
  }

  Widget _card(FeedItem item, String profileId) {
    final l = AppLocalizations.of(context);
    final local = item.occurredAt.toLocal();
    return UpFeedCard(
      mood: item.mood ?? UpMood.good,
      leadingIcon: item.entityType == 'document'
          ? Icons.description_outlined
          : item.isObservation
          ? Icons.hub_outlined
          : item.isCrisi
          ? Icons.heart_broken_outlined
          : item.mood == null
          ? Icons.arrow_upward
          : null,
      hasAttachment: item.hasAttachment,
      upId: item.entityType == 'up' ? item.entityId : null,
      coverImageIndex: item.entityType == 'up' ? item.coverImageIndex : null,
      isCrisis: item.isCrisi,
      date: DateFormat.MMMd(l.localeName).format(local),
      time: DateFormat.Hm(l.localeName).format(local),
      category:
          '${upCategoryLabel(l, item.category)}${item.isDraft
              ? ' · ${l.crisiDraftPill}'
              : item.isCrisi
              ? ' · ${l.myUpsFilterCrisis}'
              : item.isObservation
              ? ' · 360°'
              : ''}',
      categoryColor: upCategoryColor(context.colors, item.category),
      note: item.preview ?? '',
      authorLine: switch (item.author) {
        final author? when !author.isSelf => contentAuthorLine(
          l,
          author,
          added: item.entityType == 'document',
        ),
        _ => null,
      },
      onTap: item.entityType == 'document'
          ? () => widget.onOpenDocument?.call(item.entityId)
          : item.entityType == 'observation'
          ? () => _openObservation(profileId, item.entityId)
          : () => widget.onOpenUp?.call(item),
    );
  }

  Future<void> _refresh(String profileId) async {
    if (_timeline) {
      ref.read(historicMonthCacheProvider.notifier).clearProfile(profileId);
      ref.invalidate(historicMonthProvider);
    } else {
      ref.invalidate(_provider(profileId));
      try {
        await ref.read(_provider(profileId).future);
      } on AppError {
        // The provider's error state renders the retry action.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final profile = ref.watch(currentProfileProvider);
    final page = profile == null || _timeline
        ? null
        : ref.watch(_provider(profile.id));
    final patterns = profile == null || _period != 3 || _query != null
        ? null
        : ref.watch(professionalPatternsProvider(profile.id)).valueOrNull;
    final body = profile == null
        ? Center(child: Text(l.addUpNoProfile))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            key: const ValueKey('my-ups-search'),
                            controller: _search,
                            prefixIcon: Icons.search,
                            hint: l.myUpsSearchHint,
                            autocorrect: false,
                            onChanged: _setQuery,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconSquareButton(
                          icon: _filters.isEmpty
                              ? Icons.filter_alt_outlined
                              : Icons.filter_alt,
                          tooltip: l.feedFilters,
                          onPressed: () => _openFilters(profile.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedTabs(
                      labels: [
                        l.myUpsPeriodAlways,
                        l.myUpsPeriodDay,
                        l.myUpsPeriodWeek,
                        l.myUpsPeriodMonth,
                      ],
                      selectedIndex: (_period + 1) % 4,
                      onChanged: (i) => _changePeriod((i + 3) % 4),
                    ),
                    if (!widget.embedded || _type != 0)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: AppChip(
                                  label: [
                                    l.myUpsFilterAll,
                                    l.myUpsFilterUps,
                                    l.myUpsFilterArxius,
                                    l.myUpsFilterCrisis,
                                  ][i],
                                  selected: _type == i,
                                  onTap: () => setState(() => _type = i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (!_filters.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _filters = const FeedFilters()),
                          icon: const Icon(Icons.close, size: 16),
                          label: Text(l.feedClearFilters),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _refresh(profile.id),
                  child: ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      if (!_timeline && _period < 3)
                        Row(
                          children: [
                            IconButton(
                              tooltip: l.summaryPreviousPeriod,
                              onPressed: () => _setDate(_adjacentPeriod(-1)),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Text(
                                DateFormat.yMMMMd(l.localeName).format(_date),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              tooltip: l.summaryNextPeriod,
                              onPressed:
                                  _adjacentPeriod(1).isAfter(DateTime.now())
                                  ? null
                                  : () => _setDate(_adjacentPeriod(1)),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      if (_timeline)
                        UpTimeline(
                          profileId: profile.id,
                          period: _period,
                          date: _date,
                          onDate: _setDate,
                          onDay: (date) => _changePeriod(0, date: date),
                          itemBuilder: (item) => _card(item, profile.id),
                        )
                      else if (page!.isLoading)
                        const FeedRowsSkeleton()
                      else if (page.hasError) ...[
                        Text(l.feedLoadError),
                        AppButton(
                          label: l.commonRetry,
                          onPressed: () =>
                              ref.invalidate(_provider(profile.id)),
                        ),
                      ] else ...[
                        if (patterns?.isNotEmpty == true) ...[
                          AlertBanner(
                            icon: Icons.auto_awesome_outlined,
                            title: l.patronsTitle,
                            subtitle: patterns!.first.statement(l.localeName),
                            onTap: () => context.push(
                              Routes.patronDetailFor(patterns.first.id),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          _filters.origin == 'centre' || _type == 2
                              ? l.feedResults(
                                  page.requireValue.matchingCount ??
                                      page.requireValue.items.length,
                                )
                              : l.myUpsStats(
                                  page.requireValue.totalUps,
                                  page.requireValue.daysWithUps,
                                ),
                          style: TextStyle(
                            color: c.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (page.requireValue.items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 48,
                                  color: c.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _hasFilters ? l.feedNoResults : l.myUpsEmpty,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                AppButton(
                                  label: _hasFilters
                                      ? l.feedClearFilters
                                      : l.addUpTitle,
                                  onPressed: _hasFilters
                                      ? _clearFilters
                                      : () => context.push(Routes.addUp),
                                ),
                              ],
                            ),
                          ),
                        ..._groups(page.requireValue.items, profile.id),
                        if (page.requireValue.hasMore)
                          _loadingPage == _provider(profile.id)
                              ? const FeedRowsSkeleton(count: 1)
                              : AppButton(
                                  label: l.commonLoadMore,
                                  variant: AppButtonVariant.secondary,
                                  onPressed: _loadMore,
                                ),
                      ],
                      if (profile.role != 'view_only' &&
                          !profile.isHistoryOnly) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('my-ups-recently-deleted'),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            onPressed: () => context.push(Routes.deletedUps),
                            icon: const Icon(
                              Icons.restore_from_trash_outlined,
                              size: 20,
                            ),
                            label: Text(l.deletedUpsTitle),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
    return widget.embedded
        ? body
        : Scaffold(
            backgroundColor: c.surfaceCanvas,
            appBar: AppHeader(
              title: l.myUpsTitle(profile?.displayName ?? '—'),
              centerTitle: true,
              onBack: widget.onBack,
            ),
            body: body,
          );
  }

  List<Widget> _groups(List<FeedItem> items, String profileId) {
    final widgets = <Widget>[];
    DateTime? previous;
    for (final item in items) {
      final day = DateUtils.dateOnly(item.occurredAt.toLocal());
      if (day != previous) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              DateFormat.yMMMMEEEEd(
                AppLocalizations.of(context).localeName,
              ).format(day),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
      previous = day;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _card(item, profileId),
        ),
      );
    }
    return widgets;
  }
}
