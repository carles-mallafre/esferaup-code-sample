import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/core/widgets/icon_row_card.dart';
import 'package:esferaup/core/widgets/inputs/app_text_field.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'package:esferaup/features/feed/presentation/widgets/feed_skeletons.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_selector.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

const _durations = ['< 5 min', '5–15 min', '15–30 min', '> 30 min'];

/// Wire keys parallel to [_durations] (schemas/up.py DurationBucket).
const _durationKeys = ['lt5', 'five_to_15', 'fifteen_to_30', 'gt30'];

/// `Crisi emocional` (§5/§6 Art-9 sidecar). A gentle, no-pressure capture of a
/// crisis episode — when, trigger, duration, resolution, current mood. Stored
/// encrypted as a `UPCrisi` sidecar via POST /v1/profiles/{id}/crisis
/// (091-WP06). "Acabar més tard" saves a draft server-side; opening the
/// screen with [resumeUpId] loads that draft and completes it in place.
class CrisiScreen extends ConsumerStatefulWidget {
  const CrisiScreen({
    super.key,
    this.onBack,
    this.onSave,
    this.onFinishLater,
    this.initialWhen,
    this.resumeUpId,
  });

  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final VoidCallback? onFinishLater;

  /// Id of a Crisi draft to resume; null starts a new entry.
  final String? resumeUpId;

  /// Test seam: fixes the "when" moment so golden tests are deterministic.
  final DateTime? initialWhen;

  @override
  ConsumerState<CrisiScreen> createState() => _CrisiScreenState();
}

class _CrisiScreenState extends ConsumerState<CrisiScreen> {
  final _trigger = TextEditingController();
  final _resolution = TextEditingController();
  int _duration = 1;
  UpMood? _mood = UpMood.good;
  late DateTime _when = widget.initialWhen ?? DateTime.now();
  bool _saving = false;
  bool _loadingDraft = false;
  bool _draftUnavailable = false;

  bool get _resuming => widget.resumeUpId != null;

  @override
  void initState() {
    super.initState();
    if (_resuming) _loadDraft();
  }

  Future<void> _loadDraft() async {
    setState(() => _loadingDraft = true);
    try {
      final detail = await ref
          .read(upRepositoryProvider)
          .getUp(widget.resumeUpId!);
      if (!mounted) return;
      _applyDraft(detail);
    } on Object {
      if (mounted) setState(() => _draftUnavailable = true);
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  void _applyDraft(UpDetail detail) {
    final crisi = detail.crisi;
    setState(() {
      _when = detail.occurredAt;
      _trigger.text = crisi?.triggerText ?? '';
      _resolution.text = crisi?.resolutionText ?? '';
      final bucket = _durationKeys.indexOf(crisi?.durationBucket ?? '');
      if (bucket >= 0) _duration = bucket;
      _mood = crisi?.moodAfter ?? _mood;
    });
  }

  @override
  void dispose() {
    _trigger.dispose();
    _resolution.dispose();
    super.dispose();
  }

  String _whenLabel(BuildContext context) {
    final today = DateTime.now();
    final isToday =
        _when.year == today.year &&
        _when.month == today.month &&
        _when.day == today.day;
    final time = TimeOfDay.fromDateTime(_when).format(context);
    return isToday
        ? '${AppLocalizations.of(context).commonToday} · $time'
        : '${_when.day}/${_when.month}/${_when.year} · $time';
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      confirmText: AppLocalizations.of(context).commonAccept,
      cancelText: AppLocalizations.of(context).commonCancel,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
      confirmText: AppLocalizations.of(context).commonAccept,
      cancelText: AppLocalizations.of(context).commonCancel,
    );
    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  Future<void> _save({required bool draft}) async {
    final l10n = AppLocalizations.of(context);
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      showErrorSnackBar(context, l10n.addUpNoProfile);
      return;
    }
    if (!draft && _trigger.text.trim().isEmpty) {
      showErrorSnackBar(context, l10n.crisiTriggerRequired);
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(upRepositoryProvider);
      if (_resuming) {
        await repository.updateCrisi(
          upId: widget.resumeUpId!,
          occurredAt: _when,
          triggerText: _trigger.text,
          resolutionText: _resolution.text,
          durationBucket: _durationKeys[_duration],
          moodAfter: _mood,
          draft: draft,
        );
      } else {
        await repository.createCrisi(
          profileId: profile.id,
          occurredAt: _when,
          triggerText: _trigger.text,
          resolutionText: _resolution.text,
          durationBucket: _durationKeys[_duration],
          moodAfter: _mood,
          draft: draft,
        );
      }
      if (!mounted) return;
      invalidateUpReads(ref, profile.id);
      if (!_resuming) ref.invalidate(currentFamilyProvider);
      if (widget.resumeUpId case final id?) {
        ref.invalidate(upDetailControllerProvider(id));
      }
      if (draft) {
        showInfoSnackBar(context, l10n.crisiDraftSaved);
        widget.onFinishLater?.call();
      } else {
        widget.onSave?.call();
      }
    } on AppError {
      if (!mounted) return;
      showErrorSnackBar(context, l10n.crisiSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.surfaceCanvas,
      appBar: AppHeader(title: l10n.crisiTitle, onBack: widget.onBack),
      body: Column(
        children: [
          Expanded(
            child: _loadingDraft
                ? const DetailSkeleton(heroHeight: 100)
                : _draftUnavailable
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s6),
                      child: Text(
                        l10n.crisiDraftUnavailable,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s4,
                      AppSpacing.s3,
                      AppSpacing.s4,
                      AppSpacing.s6,
                    ),
                    children: [
                      _Reassurance(),
                      const SizedBox(height: AppSpacing.s5),
                      _Step(n: 1, title: l10n.crisiStep1),
                      const SizedBox(height: AppSpacing.s3),
                      IconRowCard(
                        icon: Icons.calendar_today_rounded,
                        title: _whenLabel(context),
                        subtitle: l10n.crisiTapToChangeMoment,
                        onTap: _pickWhen,
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      _Step(n: 2, title: l10n.crisiStep2),
                      const SizedBox(height: AppSpacing.s2),
                      AppTextField(
                        controller: _trigger,
                        semanticLabel: l10n.crisiStep2,
                        hint: l10n.crisiTriggerHint,
                        maxLines: 3,
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      _Step(n: 3, title: l10n.crisiStep3),
                      const SizedBox(height: AppSpacing.s3),
                      Wrap(
                        spacing: AppSpacing.s2,
                        children: [
                          for (var i = 0; i < _durations.length; i++)
                            AppChip(
                              label: _durations[i],
                              selected: i == _duration,
                              onTap: () => setState(() => _duration = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      _Step(n: 4, title: l10n.crisiStep4),
                      const SizedBox(height: AppSpacing.s2),
                      AppTextField(
                        controller: _resolution,
                        semanticLabel: l10n.crisiStep4,
                        hint: l10n.crisiResolutionHint,
                        maxLines: 3,
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      _Step(n: 5, title: l10n.crisiStep5),
                      const SizedBox(height: AppSpacing.s3),
                      MoodSelector(
                        selected: _mood,
                        onChanged: (m) => setState(() => _mood = m),
                      ),
                    ],
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceCanvas,
              border: Border(top: BorderSide(color: c.gray200)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving || _loadingDraft || _draftUnavailable
                          ? null
                          : () => _save(draft: true),
                      child: Text(
                        l10n.crisiFinishLater,
                        style: TextStyle(
                          color: c.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Expanded(
                      child: AppButton(
                        label: l10n.crisiSave,
                        variant: AppButtonVariant.danger,
                        loading: _saving,
                        onPressed: _saving || _loadingDraft || _draftUnavailable
                            ? null
                            : () => _save(draft: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reassurance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: c.errorLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.heart_broken_outlined, size: 24, color: c.warning),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.crisiReassuranceTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.warningInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.crisiReassuranceBody,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: c.errorInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title});
  final int n;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$n · ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.warning,
            ),
          ),
          TextSpan(
            text: title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}
