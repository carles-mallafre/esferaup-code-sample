import 'package:esferaup/core/utils/file_size.dart';
import 'package:esferaup/core/widgets/content_author_line.dart';
import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/bottom_action_bar.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/buttons/icon_square_button.dart';
import 'package:esferaup/core/widgets/chips/tag_pill.dart';
import 'package:esferaup/core/widgets/media/memory_only_network_image.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/features/feed/domain/entities/feed_entities.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/screens/up_edit_screen.dart';
import 'package:esferaup/features/feed/presentation/widgets/feed_skeletons.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_face.dart';
import 'package:esferaup/features/up/presentation/widgets/authenticated_up_image.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/presentation/widgets/up_deleted_snack_bar.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:esferaup/features/up/presentation/sharing/share_up.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:esferaup/core/widgets/feedback/refresh_notice.dart';

class UpDetailScreen extends ConsumerStatefulWidget {
  const UpDetailScreen({
    super.key,
    this.upId,
    this.item,
    this.childName = '',
    this.title,
    this.onBack,
    this.onDeleted,
    this.onResumeCrisi,
  });

  final String? upId;
  final FeedItem? item;
  final String childName;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onDeleted;

  /// Opens the Crisi form on an "Acabar més tard" draft.
  final ValueChanged<String>? onResumeCrisi;

  @override
  ConsumerState<UpDetailScreen> createState() => _UpDetailScreenState();
}

class _UpDetailScreenState extends ConsumerState<UpDetailScreen> {
  bool _mutating = false;

  String? get _id => widget.upId ?? widget.item?.entityId;

  Future<void> _togglePin(UpDetail detail) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _mutating = true);
    try {
      await ref
          .read(upDetailControllerProvider(detail.id).notifier)
          .setPinned(!detail.isPinned);
      if (mounted) invalidateUpReads(ref, detail.profileId);
    } on Object {
      if (mounted) _showError(l10n.upDetailPinFailed);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _delete(UpDetail detail) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.upDetailDeleteTitle),
        content: Text(l10n.upDetailDeleteRecoverable(upRecoveryDays)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.upDetailDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _mutating = true);
    try {
      await ref.read(upRepositoryProvider).deleteUp(detail.id);
      invalidateUpReadsIn(container, detail.profileId);
      container
        ..invalidate(deletedUpsProvider(detail.profileId))
        ..invalidate(upDetailControllerProvider(detail.id));
      showUpDeletedSnackBar(
        messenger: messenger,
        container: container,
        l10n: l10n,
        upId: detail.id,
        profileId: detail.profileId,
      );
      if (!mounted) return;
      widget.onDeleted?.call();
    } on Object {
      if (mounted) _showError(l10n.upDetailDeleteFailed);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _share(AppLocalizations l10n, UpDetail detail) async {
    setState(() => _mutating = true);
    try {
      await shareUp(context, ref, detail);
    } on Object {
      if (mounted) _showError(l10n.memoryActionFailed);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final id = _id;
    return Scaffold(
      backgroundColor: c.surfaceCanvas,
      appBar: AppHeader(
        title:
            widget.title ??
            (widget.childName.isEmpty
                ? l10n.upDetailTitleGeneric
                : l10n.upDetailTitle(widget.childName)),
        centerTitle: true,
        onBack: widget.onBack,
      ),
      body: id == null
          ? _ErrorState(message: l10n.upDetailLoadError, retry: null)
          : ref
                .watch(upDetailControllerProvider(id))
                .when(
                  loading: () => const DetailSkeleton(),
                  error: (error, _) => _ErrorState(
                    message: error is NetworkError
                        ? l10n.commonNoConnection
                        : l10n.upDetailLoadError,
                    retry: () => ref.invalidate(upDetailControllerProvider(id)),
                  ),
                  data: (detail) => _body(detail),
                ),
    );
  }

  Widget _body(UpDetail detail) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final mood = detail.crisi?.moodAfter ?? detail.mood ?? UpMood.good;
    final category = upCategoryLabel(l10n, detail.category);
    final profile = ref
        .watch(currentFamilyProvider)
        .valueOrNull
        ?.profiles
        .where((profile) => profile.id == detail.profileId)
        .firstOrNull;
    final canEdit =
        profile?.role != 'view_only' && profile?.isHistoryOnly != true;
    final when = MaterialLocalizations.of(
      context,
    ).formatFullDate(detail.occurredAt);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => refreshOrNotify(context, () async {
          ref.read(upDetailControllerProvider(detail.id).notifier).refresh();
          await ref.read(upDetailControllerProvider(detail.id).future);
        }),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s6,
          ),
          children: [
            _UpHero(
              detail: detail,
              mood: mood,
              label: '${upMoodLabel(l10n, mood)} · $category',
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(when, style: TextStyle(fontSize: 15, color: c.textMuted)),
            if (detail.author case final author?) ...[
              const SizedBox(height: AppSpacing.s1),
              ContentAuthorLine(author: author),
            ],
            const SizedBox(height: AppSpacing.s3),
            if (detail.crisi case final crisi?)
              _CrisiSection(crisi: crisi)
            else
              Text(
                detail.note?.trim().isNotEmpty == true
                    ? detail.note!
                    : l10n.upDetailNoNote,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: c.textStrong,
                ),
              ),
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s2,
              children: [
                TagPill(label: category),
                if (detail.tag case final tag?) TagPill(label: tag),
                if (detail.isCrisi) TagPill(label: l10n.addUpCrisi),
                if (detail.isCrisiDraft) TagPill(label: l10n.crisiDraftPill),
                if (detail.isPinned) TagPill(label: l10n.esferesTabMemories),
              ],
            ),
            if (canEdit &&
                detail.isCrisiDraft &&
                widget.onResumeCrisi != null) ...[
              const SizedBox(height: AppSpacing.s4),
              AppButton(
                label: l10n.crisiResumeCta,
                icon: Icons.edit_note_rounded,
                onPressed: () => widget.onResumeCrisi!(detail.id),
              ),
            ],
            if (detail.attachments.isNotEmpty || detail.attachmentsPending) ...[
              const SizedBox(height: AppSpacing.s5),
              Text(
                l10n.addUpAttachments,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.textStrong,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
              if (detail.attachmentsPending) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.upDetailAttachmentsPending,
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
              ],
              for (final attachment in detail.attachments) ...[
                _AttachmentCard(upId: detail.id, attachment: attachment),
                const SizedBox(height: AppSpacing.s3),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            if (canEdit && !detail.isCrisi) ...[
              IconSquareButton(
                icon: Icons.edit_outlined,
                tooltip: l10n.upDetailEdit,
                onPressed: _mutating
                    ? null
                    : () => Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => UpEditScreen(detail: detail),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.s2),
            ],
            IconSquareButton(
              icon: Icons.ios_share_rounded,
              tooltip: l10n.upDetailShare,
              onPressed: _mutating ? null : () => _share(l10n, detail),
            ),
            const SizedBox(width: AppSpacing.s2),
            IconSquareButton(
              icon: Icons.delete_outline_rounded,
              tooltip: l10n.upDetailDelete,
              onPressed: _mutating || !canEdit ? null : () => _delete(detail),
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: AppButton(
                label: detail.isPinned ? l10n.upDetailUnpin : l10n.upDetailPin,
                icon: detail.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                loading: _mutating,
                onPressed: _mutating || !canEdit
                    ? null
                    : () => _togglePin(detail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrisiSection extends StatelessWidget {
  const _CrisiSection({required this.crisi});

  final UpCrisiDetail crisi;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final entries = [
      (l10n.upDetailCrisiTrigger, crisi.triggerText),
      (l10n.upDetailCrisiResolution, crisi.resolutionText),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, body) in entries) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            body?.trim().isNotEmpty == true ? body! : l10n.upDetailCrisiEmpty,
            style: TextStyle(fontSize: 16, height: 1.45, color: c.textStrong),
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
      ],
    );
  }
}

class _AttachmentCard extends ConsumerWidget {
  const _AttachmentCard({required this.upId, required this.attachment});

  final String upId;
  final UpAttachment attachment;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final grant = await ref
          .read(upRepositoryProvider)
          .getAttachmentDownloadGrant(
            upId: upId,
            attachmentIndex: attachment.index,
          );
      if (!grant.isSafeHttp ||
          !grant.expiresAt.isAfter(
            DateTime.now().add(const Duration(seconds: 2)),
          )) {
        throw const FormatException('unsafe or expired attachment grant');
      }
      if (!context.mounted) return;
      if (attachment.isImage) {
        final imageSource = MemoryOnlyNetworkImageSource(
          grant.url,
          cacheWidth: 1600,
        );
        try {
          await showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder: (dialogContext) => Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: MemoryOnlyNetworkImage(
                          source: imageSource,
                          fit: BoxFit.contain,
                          placeholder: const CircularProgressIndicator(
                            color: Colors.white,
                          ),
                          error: Text(
                            l10n.upDetailAttachmentUnavailable,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.s2,
                      right: AppSpacing.s2,
                      child: IconButton.filled(
                        tooltip: l10n.commonClose,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } finally {
          await imageSource.evict();
        }
      } else if (!await launchUrl(
        grant.url,
        mode: LaunchMode.externalApplication,
      )) {
        throw const FormatException('no safe attachment viewer');
      }
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.upDetailAttachmentUnavailable)),
      );
    }
  }

  String _kind(AppLocalizations l10n) => attachment.isImage
      ? l10n.upAttachmentKindImage
      : attachment.isAudio
      ? l10n.upAttachmentKindAudio
      : attachment.mime == 'application/pdf'
      ? 'PDF'
      : l10n.upAttachmentKindFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.upDetailAttachmentLabel(attachment.index + 1),
      child: Material(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _open(context, ref),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(AppSpacing.s3),
            decoration: BoxDecoration(
              border: Border.all(color: c.surfaceBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  attachment.isImage
                      ? Icons.image_outlined
                      : attachment.isAudio
                      ? Icons.mic_none_rounded
                      : attachment.mime == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.insert_drive_file_outlined,
                  color: c.primary,
                  size: 30,
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.upDetailAttachmentLabel(attachment.index + 1),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.textStrong,
                        ),
                      ),
                      Text(
                        '${_kind(l10n)} · ${formatFileSize(attachment.sizeBytes, l10n.localeName)}',
                        style: TextStyle(fontSize: 13, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new_rounded, color: c.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpHero extends StatelessWidget {
  const _UpHero({
    required this.detail,
    required this.mood,
    required this.label,
  });

  final UpDetail detail;
  final UpMood mood;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final image = detail.attachments
        .where((attachment) => attachment.isImage)
        .firstOrNull;
    final placeholder = Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: c.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        spacing: AppSpacing.s3,
        runSpacing: AppSpacing.s3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          MoodFace(mood: mood, size: 72),
          Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: c.textStrong,
            ),
          ),
        ],
      ),
    );
    if (image == null) return placeholder;
    return Semantics(
      image: true,
      label: label,
      // The same words are painted over the photo below; without this a reader
      // hears the mood and category twice.
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 220,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AuthenticatedUpImage(
                upId: detail.id,
                attachmentIndex: image.index,
                placeholder: placeholder,
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceCard,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});

  final String message;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (retry != null) ...[
            const SizedBox(height: AppSpacing.s3),
            OutlinedButton(
              onPressed: retry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ],
      ),
    ),
  );
}
