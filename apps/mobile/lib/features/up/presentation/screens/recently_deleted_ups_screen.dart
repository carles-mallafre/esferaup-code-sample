import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/theme/category_colors.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'package:esferaup/features/feed/presentation/widgets/feed_skeletons.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/widgets/up_feed_card.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:esferaup/core/widgets/feedback/refresh_notice.dart';

/// UPs deleted in the last [upRecoveryDays] days, each with a Restore action.
class RecentlyDeletedUpsScreen extends ConsumerStatefulWidget {
  const RecentlyDeletedUpsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  ConsumerState<RecentlyDeletedUpsScreen> createState() =>
      _RecentlyDeletedUpsScreenState();
}

class _RecentlyDeletedUpsScreenState
    extends ConsumerState<RecentlyDeletedUpsScreen> {
  String? _restoringId;

  Future<void> _restore(DeletedUp up) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _restoringId = up.id);
    try {
      await ref.read(upRepositoryProvider).restoreUp(up.id);
      if (!mounted) return;
      invalidateUpReads(ref, up.profileId);
      ref
        ..invalidate(deletedUpsProvider(up.profileId))
        ..invalidate(upDetailControllerProvider(up.id));
      showInfoSnackBar(context, l10n.upRestored);
    } on AppError catch (e) {
      if (!mounted) return;
      final expired = e.code == 'UP_RESTORE_WINDOW_EXPIRED';
      final block = UpRestoreBlock.fromErrorCode(e.code);
      // The list was read before the profile's state changed: read it again
      // so the row shows the reason instead of the action.
      if (expired || block != null) {
        ref.invalidate(deletedUpsProvider(up.profileId));
      }
      showErrorSnackBar(
        context,
        expired
            ? l10n.upRestoreExpired
            : block != null
            ? upRestoreBlockMessage(l10n, block)
            : l10n.upRestoreFailed,
      );
    } on Object {
      if (mounted) showErrorSnackBar(context, l10n.upRestoreFailed);
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(
      backgroundColor: c.surfaceCanvas,
      appBar: AppHeader(
        title: l10n.deletedUpsTitle,
        centerTitle: true,
        onBack: widget.onBack,
      ),
      body: profile == null
          ? Center(child: Text(l10n.addUpNoProfile))
          : _body(context, l10n, profile.id),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, String profileId) {
    final c = context.colors;
    final deleted = ref.watch(deletedUpsProvider(profileId));
    return RefreshIndicator(
      onRefresh: () => refreshOrNotify(
        context,
        () => ref.refresh(deletedUpsProvider(profileId).future),
      ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            l10n.deletedUpsIntro(upRecoveryDays),
            style: TextStyle(color: c.textMuted),
          ),
          const SizedBox(height: AppSpacing.s4),
          ...deleted.when(
            loading: () => const [FeedRowsSkeleton()],
            error: (_, _) => [
              Semantics(
                liveRegion: true,
                child: Text(l10n.deletedUpsLoadError),
              ),
              const SizedBox(height: AppSpacing.s3),
              AppButton(
                label: l10n.commonRetry,
                icon: Icons.refresh_rounded,
                onPressed: () => ref.invalidate(deletedUpsProvider(profileId)),
              ),
            ],
            data: (items) => items.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.restore_from_trash_outlined,
                            size: 48,
                            color: c.primary,
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            l10n.deletedUpsEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ]
                : [for (final up in items) _row(context, l10n, up)],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, DeletedUp up) {
    final c = context.colors;
    final date = DateFormat.MMMd(l10n.localeName).format(up.occurredAt);
    final busy = _restoringId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UpFeedCard(
            mood: up.mood ?? UpMood.good,
            leadingIcon: up.isCrisi
                ? Icons.heart_broken_outlined
                : up.mood == null
                ? Icons.arrow_upward
                : null,
            hasAttachment: up.hasAttachment,
            isCrisis: up.isCrisi,
            date: date,
            time: DateFormat.Hm(l10n.localeName).format(up.occurredAt),
            category:
                '${upCategoryLabel(l10n, up.category)}${up.isCrisi ? ' · ${l10n.myUpsFilterCrisis}' : ''}',
            categoryColor: upCategoryColor(c, up.category),
            note: up.preview ?? '',
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.deletedUpsDaysLeft(up.daysLeft),
                  style: TextStyle(
                    color: c.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (up.restoreBlock == null) ...[
                const SizedBox(width: AppSpacing.s2),
                Semantics(
                  container: true,
                  label: l10n.deletedUpsRestoreSemantics(date),
                  button: true,
                  excludeSemantics: true,
                  onTap: busy ? null : () => _restore(up),
                  child: AppButton(
                    key: ValueKey('restore-${up.id}'),
                    label: l10n.deletedUpsRestore,
                    icon: Icons.restore_rounded,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    fullWidth: false,
                    loading: _restoringId == up.id,
                    onPressed: busy ? null : () => _restore(up),
                  ),
                ),
              ],
            ],
          ),
          if (up.restoreBlock case final block?) ...[
            const SizedBox(height: AppSpacing.s2),
            Row(
              key: ValueKey('restore-blocked-${up.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    upRestoreBlockMessage(l10n, block),
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
