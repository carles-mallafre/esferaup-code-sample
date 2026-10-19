import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'dart:async';

import 'package:esferaup/features/up/presentation/widgets/pending_attachment_tile.dart';

import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:esferaup/core/upload/upload_providers.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/core/widgets/icon_row_card.dart';
import 'package:esferaup/core/widgets/inputs/app_text_field.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/core/widgets/option_picker_sheet.dart';
import 'package:esferaup/core/widgets/profile_pill.dart';
import 'package:esferaup/features/family/domain/entities/family.dart';
import 'package:esferaup/features/family/presentation/providers/family_providers.dart';
import 'package:esferaup/features/family/presentation/widgets/profile_avatar.dart';
import 'package:esferaup/features/family/presentation/widgets/profile_switch_sheet.dart';
import 'package:esferaup/features/notifications/presentation/providers/push_notification_controller.dart';
import 'package:esferaup/features/up/data/up_attachment_picker.dart';
import 'package:esferaup/features/up/data/up_audio_capture.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/domain/up_tag.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/widgets/arxiu_info_sheet.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_selector.dart';
import 'package:esferaup/features/up/presentation/widgets/up_date_sheet.dart';
import 'package:esferaup/features/up/presentation/widgets/capture_permission_sheet.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

/// Stable wire vocabulary (schemas/up.py UPCategory).
const _categoryKeys = [
  'casa',
  'escola',
  'emocions',
  'esport',
  'salut',
  'activa',
  'nutricio',
  'descans',
];

/// `6 · Add UP (capture)` (§18.x). The core action: pick a profile + date, a
/// mood, a category, an optional note + attachments, then save (POST
/// /v1/profiles/{id}/ups — 091-WP06). "Crisi" opens the Art-9 crisis sidecar.
class AddUpScreen extends ConsumerStatefulWidget {
  const AddUpScreen({super.key, this.onClose, this.onSaved, this.onCrisi});

  final VoidCallback? onClose;

  /// Called after a successful save with the chosen category label (the Guardat
  /// screen shows which esfera grew).
  final void Function(String upId, String esfera)? onSaved;
  final VoidCallback? onCrisi;

  @override
  ConsumerState<AddUpScreen> createState() => _AddUpScreenState();
}

class _AddUpScreenState extends ConsumerState<AddUpScreen> {
  final _note = TextEditingController();
  final _tag = TextEditingController();
  final _scroll = ScrollController();
  bool _tagInvalid = false;
  final List<_PendingAttachment> _attachments = [];
  bool _saveToArxiu = false;
  late final SensitiveTempFileStore _tempFiles;
  late final UpAudioCaptureController _audioController;
  UpMood? _mood = UpMood.good;
  int _category = 2; // Emocions, per the Figma default
  DateTime _date = DateTime.now();
  bool _saving = false;
  _PendingAttachment? _audioAttachment;

  @override
  void initState() {
    super.initState();
    _tempFiles = ref.read(sensitiveTempFileStoreProvider);
    _audioController = ref.read(upAudioCaptureControllerProvider);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!validUpTag(_tag.text)) {
      setState(() => _tagInvalid = true);
      return;
    }
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      showErrorSnackBar(context, l10n.addUpNoProfile);
      return;
    }
    if (profile.role == 'view_only' || profile.isHistoryOnly) {
      showErrorSnackBar(
        context,
        profile.isHistoryOnly ? l10n.addUpHistoryOnly : l10n.addUpReadOnly,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uploadKeys = await _uploadAttachments(profile.id);
      final result = await ref
          .read(upRepositoryProvider)
          .createUp(
            profileId: profile.id,
            category: _categoryKeys[_category],
            occurredAt: _date,
            mood: _mood,
            note: _note.text,
            tag: _tag.text,
            attachmentUploadKeys: uploadKeys,
            saveToArxiu:
                _saveToArxiu && _attachments.any((a) => !a.picked.isAudio),
          );
      if (!mounted) return;
      await ref
          .read(pushNotificationControllerProvider.notifier)
          .onFirstUpPersisted();
      if (!mounted) return;
      await Future.wait([
        for (final attachment in _allPendingAttachments())
          _tempFiles.delete(attachment.picked.file),
      ]);
      await _audioController.discard();
      if (!mounted) return;
      invalidateUpReads(ref, profile.id);
      ref.invalidate(currentFamilyProvider);
      widget.onSaved?.call(result.id, _categoryLabel(l10n, _category));
    } on MigrationLockedError {
      // The app-wide write-block dialog already explains the refusal; the
      // connection snackbar on top of it would contradict it.
    } on Object {
      if (!mounted) return;
      showErrorSnackBar(context, l10n.addUpSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _tag.dispose();
    _scroll.dispose();
    for (final attachment in _attachments) {
      unawaited(_tempFiles.delete(attachment.picked.file));
    }
    unawaited(_audioController.discard());
    super.dispose();
  }

  bool get _wouldLoseAudio {
    final audio = _audioController.state;
    return audio.completed != null ||
        audio.phase == UpAudioCapturePhase.recording ||
        audio.phase == UpAudioCapturePhase.interrupted;
  }

  Future<bool> _confirmDiscardAudio() async {
    if (!_wouldLoseAudio) return true;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addUpDiscardAudioTitle),
        content: Text(l10n.addUpDiscardAudioBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.addUpAudioDiscard),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _close() async {
    if (await _confirmDiscardAudio() && mounted) widget.onClose?.call();
  }

  Future<List<String>> _uploadAttachments(String profileId) async {
    final transport = ref.read(uploadTransportProvider);
    _syncCompletedAudio();
    for (final attachment in _allPendingAttachments()) {
      if (attachment.uploadKey != null) continue;
      final uploaded = await transport.uploadFile(
        context: attachment.picked.uploadContext,
        profileId: profileId,
        file: attachment.picked.file,
        mime: attachment.picked.mime,
      );
      attachment.uploadKey = uploaded.uploadKey;
    }
    return [
      for (final attachment in _allPendingAttachments()) attachment.uploadKey!,
    ];
  }

  List<_PendingAttachment> _allPendingAttachments() {
    final audio = _audioController.state.completed;
    final pendingAudio = _audioAttachment;
    return [
      ..._attachments,
      if (audio != null && pendingAudio?.picked.file.path == audio.file.path)
        pendingAudio!,
    ];
  }

  void _syncCompletedAudio() {
    final completed = _audioController.state.completed;
    if (completed == null) {
      _audioAttachment = null;
    } else if (_audioAttachment?.picked.file.path != completed.file.path) {
      _audioAttachment = _PendingAttachment(completed);
    }
  }

  Future<void> _switchProfile(Family family) async {
    final picked = await showProfileSwitchSheet(
      context: context,
      family: family,
      selectedId: ref.read(currentProfileProvider)?.id,
    );
    if (picked != null) {
      ref.read(selectedProfileProvider.notifier).select(picked);
    }
  }

  Future<void> _pickPhoto() async {
    final l10n = AppLocalizations.of(context);
    final source = await showOptionPicker<UpAttachmentPickSource>(
      context: context,
      title: l10n.addUpPhoto,
      selected: UpAttachmentPickSource.gallery,
      options: [
        PickerOption(
          value: UpAttachmentPickSource.camera,
          label: l10n.addUpTakePhoto,
        ),
        PickerOption(
          value: UpAttachmentPickSource.gallery,
          label: l10n.addUpChoosePhoto,
        ),
      ],
    );
    if (source != null) await _pickAttachment(source);
  }

  Future<void> _pickAttachment(UpAttachmentPickSource source) async {
    final l10n = AppLocalizations.of(context);
    if (_attachmentCount >= 5) {
      showErrorSnackBar(context, l10n.addUpAttachmentLimit);
      return;
    }
    try {
      if (source == UpAttachmentPickSource.camera &&
          !(await Permission.camera.status).isGranted) {
        if (!mounted) return;
        final proceed = await showCapturePermissionSheet(
          context,
          icon: Icons.camera_alt_outlined,
          title: l10n.upCameraTitle,
          body: l10n.upCameraBody,
        );
        if (proceed != true || !mounted) return;
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.upCameraDenied),
                persist: false,
                action: SnackBarAction(
                  label: l10n.addUpAudioOpenSettings,
                  onPressed: openAppSettings,
                ),
              ),
            );
          }
          return;
        }
      }
      final picked = await ref.read(upAttachmentPickerProvider).pick(source);
      if (picked != null && mounted) {
        if (_attachmentCount >= 5) {
          await _tempFiles.delete(picked.file);
          if (mounted) showErrorSnackBar(context, l10n.addUpAttachmentLimit);
          return;
        }
        setState(() => _attachments.add(_PendingAttachment(picked)));
      }
    } on Object {
      if (mounted) showErrorSnackBar(context, l10n.addUpAttachmentPickFailed);
    }
  }

  Future<void> _startAudio() async {
    final l10n = AppLocalizations.of(context);
    final controller = _audioController;
    if (_attachmentCount >= 5) {
      showErrorSnackBar(context, l10n.addUpAttachmentLimit);
      return;
    }
    await controller.initialize();
    if (!mounted || controller.state.phase == UpAudioCapturePhase.unavailable) {
      return;
    }
    var permission = controller.state.permission;
    if (permission == UpAudioPermissionState.notDetermined) {
      final shouldRequest = await showCapturePermissionSheet(
        context,
        icon: Icons.mic_none_rounded,
        title: l10n.addUpAudioPermissionTitle,
        body: l10n.addUpAudioPermissionBody,
      );
      if (shouldRequest != true || !mounted) return;
      permission = await controller.requestPermission();
    } else if (permission == UpAudioPermissionState.denied) {
      permission = await controller.requestPermission();
    }
    if (!mounted || permission != UpAudioPermissionState.granted) return;
    await controller.start();
    // The recording panel opens below the attachment buttons, under the bar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  int get _attachmentCount =>
      _attachments.length + (_audioController.state.completed == null ? 0 : 1);

  Future<void> _stopAudio() async {
    final controller = _audioController;
    await controller.stop();
    if (!mounted) return;
    setState(_syncCompletedAudio);
  }

  Future<void> _discardAudio() async {
    await _audioController.discard();
    if (!mounted) return;
    setState(() => _audioAttachment = null);
  }

  Future<void> _removeAttachment(_PendingAttachment attachment) async {
    setState(() => _attachments.remove(attachment));
    await _tempFiles.delete(attachment.picked.file);
  }

  int _age(DateTime dob) {
    final now = DateTime.now();
    var a = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      a--;
    }
    return a;
  }

  String _dateLabel(DateTime d) {
    final today = DateTime.now();
    final isToday =
        d.year == today.year && d.month == today.month && d.day == today.day;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final pretty =
        (d.year == today.year
                ? DateFormat.MMMMd(locale)
                : DateFormat.yMMMMd(locale))
            .format(d);
    return isToday ? '${l10n.commonToday} · $pretty' : pretty;
  }

  String _categoryLabel(AppLocalizations l10n, int index) =>
      switch (_categoryKeys[index]) {
        'casa' => l10n.upCategoryHome,
        'escola' => l10n.upCategorySchool,
        'emocions' => l10n.upCategoryEmotions,
        'esport' => l10n.upCategorySport,
        'salut' => l10n.upCategoryHealth,
        'activa' => l10n.upCategoryActiva,
        'nutricio' => l10n.upCategoryNutrition,
        'descans' => l10n.upCategoryRest,
        _ => _categoryKeys[index],
      };

  Future<void> _pickDate() async {
    final picked = await showUpDateSheet(context, _date);
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final profile = ref.watch(currentProfileProvider);
    final audioController = ref.watch(upAudioCaptureControllerProvider);
    final audioState = audioController.state;
    final audioBusy =
        audioState.phase == UpAudioCapturePhase.checking ||
        audioState.phase == UpAudioCapturePhase.requestingPermission ||
        audioState.phase == UpAudioCapturePhase.recording ||
        audioState.phase == UpAudioCapturePhase.interrupted;
    final pillLabel = profile == null
        ? l10n.addUpMyProfile
        : '${profile.displayName}${profile.dob == null ? '' : ' · ${l10n.iniciAge(_age(profile.dob!))}'}';
    final initial = (profile?.displayName.trim().isNotEmpty ?? false)
        ? profile!.displayName.trim().characters.first.toUpperCase()
        : '·';

    if (profile?.role == 'view_only' || profile?.isHistoryOnly == true) {
      return Scaffold(
        backgroundColor: c.surfaceCanvas,
        appBar: AppHeader(
          title: l10n.addUpTitle,
          centerTitle: true,
          leadingIcon: Icons.close,
          onBack: widget.onClose,
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ProfilePill(
                label: pillLabel,
                initial: initial,
                onTap: family == null ? null : () => _switchProfile(family),
              ),
            ),
            const SizedBox(height: AppSpacing.s5),
            Text(
              profile!.isHistoryOnly
                  ? l10n.addUpHistoryOnly
                  : l10n.addUpReadOnly,
              style: TextStyle(fontSize: 16, height: 1.5, color: c.textStrong),
            ),
          ],
        ),
      );
    }

    final screen = Scaffold(
      backgroundColor: c.surfaceCanvas,
      appBar: AppHeader(
        title: l10n.addUpTitle,
        centerTitle: true,
        leadingIcon: Icons.close,
        onBack: widget.onClose == null ? null : _close,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s6,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ProfilePill(
                    label: pillLabel,
                    initial: initial,
                    avatar: profile == null || profile.photoVersion == null
                        ? null
                        : ProfileAvatar(
                            profileId: profile.id,
                            name: profile.displayName,
                            photoVersion: profile.photoVersion,
                            radius: 12,
                            fontSize: 11,
                          ),
                    onTap: family == null ? null : () => _switchProfile(family),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                IconRowCard(
                  icon: Icons.calendar_today_rounded,
                  title: _dateLabel(_date),
                  subtitle: l10n.addUpTapToChangeDate,
                  onTap: _pickDate,
                ),
                const SizedBox(height: AppSpacing.s5),
                _SectionHeader(
                  title: l10n.addUpMoodTitle,
                  trailing: l10n.addUpMoodHint,
                ),
                const SizedBox(height: AppSpacing.s3),
                MoodSelector(
                  selected: _mood,
                  onChanged: (m) => setState(() => _mood = m),
                ),
                const SizedBox(height: AppSpacing.s5),
                _SectionHeader(title: l10n.addUpCategory),
                const SizedBox(height: AppSpacing.s3),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columnWidth =
                        (constraints.maxWidth - AppSpacing.s2 * 3) / 4;
                    final fits = List.generate(_categoryKeys.length, (i) {
                      final painter = TextPainter(
                        text: TextSpan(
                          text: _categoryLabel(l10n, i),
                          style: DefaultTextStyle.of(context).style.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final width = painter.width;
                      painter.dispose();
                      return width + 12 <= columnWidth;
                    }).every((fits) => fits);
                    return Wrap(
                      spacing: AppSpacing.s2,
                      children: [
                        for (var i = 0; i < _categoryKeys.length; i++)
                          SizedBox(
                            width: fits ? columnWidth : null,
                            child: AppChip(
                              horizontalPadding: 6,
                              label: _categoryLabel(l10n, i),
                              selected: i == _category,
                              onTap: () => setState(() => _category = i),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.s5),
                _SectionHeader(
                  title: l10n.addUpNoteTitle,
                  trailing: l10n.addUpOptional,
                ),
                const SizedBox(height: AppSpacing.s2),
                AppTextField(
                  controller: _note,
                  semanticLabel: l10n.addUpNoteTitle,
                  hint: l10n.addUpNoteHint,
                  maxLines: 2,
                  inputFormatters: [LengthLimitingTextInputFormatter(8000)],
                ),
                const SizedBox(height: AppSpacing.s5),
                _SectionHeader(
                  title: l10n.upTagTitle,
                  trailing: l10n.addUpOptional,
                ),
                const SizedBox(height: AppSpacing.s2),
                AppTextField(
                  controller: _tag,
                  semanticLabel: l10n.upTagTitle,
                  hint: l10n.upTagHint,
                  errorText: _tagInvalid ? l10n.upTagInvalid : null,
                  autocorrect: false,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  onChanged: (_) {
                    if (_tagInvalid) setState(() => _tagInvalid = false);
                  },
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  l10n.upTagHelp,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: AppSpacing.s5),
                _SectionHeader(title: l10n.addUpAttachments),
                const SizedBox(height: AppSpacing.s3),
                if (_attachments.isNotEmpty ||
                    audioState.completed != null) ...[
                  Wrap(
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
                    children: [
                      for (final attachment in _attachments)
                        PendingAttachmentTile(
                          attachment: attachment.picked,
                          onRemove: _saving
                              ? null
                              : () => _removeAttachment(attachment),
                        ),
                      if (audioState.completed != null)
                        InputChip(
                          avatar: const Icon(Icons.mic_none_rounded, size: 18),
                          label: Text(
                            l10n.addUpAudioReady(audioState.elapsed.inSeconds),
                          ),
                          onDeleted: _saving ? null : _discardAudio,
                          deleteButtonTooltipMessage:
                              l10n.addUpRemoveAttachment,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                if (_attachments.any((a) => !a.picked.isAudio)) ...[
                  _ArxiuCheckboxRow(
                    value: _saveToArxiu,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _saveToArxiu = value),
                    onInfo: () => showArxiuInfoSheet(context),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                _AttachmentActions(
                  photo: _saving || audioBusy ? null : _pickPhoto,
                  file: _saving || audioBusy
                      ? null
                      : () => _pickAttachment(UpAttachmentPickSource.pdf),
                  audio: _saving || audioBusy || audioState.completed != null
                      ? null
                      : _startAudio,
                ),
                if (_showAudioPanel(audioState)) ...[
                  const SizedBox(height: AppSpacing.s3),
                  _AudioCapturePanel(
                    state: audioState,
                    onStop: _stopAudio,
                    onDiscard: _discardAudio,
                    onResume: audioController.resume,
                    onRetry: _startAudio,
                    onOpenSettings: () async {
                      await audioController.openSettings();
                    },
                  ),
                ],
              ],
            ),
          ),
          _BottomBar(
            onCrisi: widget.onCrisi,
            saving: _saving,
            onSave: _mood == null || _saving || audioBusy ? null : _save,
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_wouldLoseAudio,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmDiscardAudio() || !context.mounted) {
          return;
        }
        final onClose = widget.onClose;
        onClose == null ? Navigator.of(context).pop() : onClose();
      },
      child: screen,
    );
  }

  bool _showAudioPanel(UpAudioCaptureState state) =>
      state.phase == UpAudioCapturePhase.requestingPermission ||
      state.phase == UpAudioCapturePhase.recording ||
      state.phase == UpAudioCapturePhase.interrupted ||
      state.phase == UpAudioCapturePhase.unavailable ||
      state.phase == UpAudioCapturePhase.failed ||
      (state.phase == UpAudioCapturePhase.idle &&
          (state.permission == UpAudioPermissionState.denied ||
              state.permission == UpAudioPermissionState.permanentlyDenied));
}

class _PendingAttachment {
  _PendingAttachment(this.picked);

  final PickedUpAttachment picked;
  String? uploadKey;
}

/// Figma "Add UP · Amb adjunt": file the attachment in the family Arxiu too.
class _ArxiuCheckboxRow extends StatelessWidget {
  const _ArxiuCheckboxRow({
    required this.value,
    required this.onChanged,
    required this.onInfo,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              key: const ValueKey('add-up-save-to-arxiu'),
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (next) => onChanged!(next ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: AppSpacing.s2),
              title: Text(
                l10n.addUpSaveToArxiu,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textStrong,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.arxiuInfoTitle,
            icon: Icon(Icons.info_outline_rounded, color: c.textMuted),
            onPressed: onInfo,
          ),
        ],
      ),
    );
  }
}

class _AttachmentActions extends StatelessWidget {
  const _AttachmentActions({this.photo, this.file, this.audio});

  final VoidCallback? photo;
  final VoidCallback? file;
  final VoidCallback? audio;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      AppButton(
        label: l10n.addUpPhoto,
        variant: AppButtonVariant.secondary,
        icon: Icons.photo_camera_outlined,
        onPressed: photo,
      ),
      AppButton(
        label: l10n.addUpFile,
        variant: AppButtonVariant.secondary,
        icon: Icons.attach_file_rounded,
        onPressed: file,
      ),
      AppButton(
        label: l10n.addUpAudio,
        variant: AppButtonVariant.secondary,
        icon: Icons.mic_none_rounded,
        onPressed: audio,
      ),
    ];
    final labels = [l10n.addUpPhoto, l10n.addUpFile, l10n.addUpAudio];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final largeText = textScaler.scale(16) >= 24;
        final style = DefaultTextStyle.of(context).style.merge(
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        );
        var widestLabel = 0.0;
        for (final label in labels) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          if (painter.width > widestLabel) widestLabel = painter.width;
          painter.dispose();
        }
        // AppButton: horizontal padding, 20 pt icon, icon gap and border.
        final buttonWidth =
            2 * AppSpacing.s4 + 20 + AppSpacing.s2 + widestLabel + 2;
        final rowFits =
            buttonWidth * actions.length +
                AppSpacing.s2 * (actions.length - 1) <=
            constraints.maxWidth;
        if (largeText || !rowFits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                actions[i],
                if (i != actions.length - 1)
                  const SizedBox(height: AppSpacing.s2),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              Expanded(child: actions[i]),
              if (i != actions.length - 1) const SizedBox(width: AppSpacing.s2),
            ],
          ],
        );
      },
    );
  }
}

class _AudioCapturePanel extends StatelessWidget {
  const _AudioCapturePanel({
    required this.state,
    required this.onStop,
    required this.onDiscard,
    required this.onResume,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final UpAudioCaptureState state;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final presentation = _presentation(l10n);
    return Semantics(
      container: true,
      liveRegion: true,
      label: presentation.$1,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: c.surfaceCard,
          border: Border.all(color: c.surfaceBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.phase == UpAudioCapturePhase.requestingPermission)
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(_icon(), color: c.primary),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.$1,
                        style: TextStyle(
                          color: c.textStrong,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (presentation.$2 != null) ...[
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          presentation.$2!,
                          style: TextStyle(color: c.textMuted, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_actions(l10n).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s3),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: _actions(l10n),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, String?) _presentation(AppLocalizations l10n) {
    if (state.phase == UpAudioCapturePhase.recording) {
      return (l10n.addUpAudioRecording(state.elapsed.inSeconds), null);
    }
    if (state.phase == UpAudioCapturePhase.interrupted) {
      return (l10n.addUpAudioInterruptedTitle, l10n.addUpAudioInterruptedBody);
    }
    if (state.phase == UpAudioCapturePhase.unavailable) {
      return (l10n.addUpAudioUnavailableTitle, l10n.addUpAudioUnavailableBody);
    }
    if (state.phase == UpAudioCapturePhase.failed) {
      return (l10n.addUpAudioFailedTitle, l10n.addUpAudioFailedBody);
    }
    if (state.permission == UpAudioPermissionState.permanentlyDenied) {
      return (l10n.addUpAudioBlockedTitle, l10n.addUpAudioBlockedBody);
    }
    if (state.permission == UpAudioPermissionState.denied) {
      return (l10n.addUpAudioDeniedTitle, l10n.addUpAudioDeniedBody);
    }
    return (l10n.addUpAudioPermissionTitle, l10n.addUpAudioPermissionBody);
  }

  IconData _icon() => switch (state.phase) {
    UpAudioCapturePhase.recording => Icons.fiber_manual_record_rounded,
    UpAudioCapturePhase.interrupted => Icons.pause_circle_outline_rounded,
    UpAudioCapturePhase.failed ||
    UpAudioCapturePhase.unavailable => Icons.mic_off_outlined,
    _ => Icons.mic_none_rounded,
  };

  List<Widget> _actions(AppLocalizations l10n) {
    if (state.phase == UpAudioCapturePhase.recording) {
      return [
        TextButton(onPressed: onDiscard, child: Text(l10n.addUpAudioDiscard)),
        FilledButton(onPressed: onStop, child: Text(l10n.addUpAudioStop)),
      ];
    }
    if (state.phase == UpAudioCapturePhase.interrupted) {
      return [
        TextButton(onPressed: onDiscard, child: Text(l10n.addUpAudioDiscard)),
        FilledButton(onPressed: onResume, child: Text(l10n.addUpAudioResume)),
      ];
    }
    if (state.phase == UpAudioCapturePhase.failed ||
        state.permission == UpAudioPermissionState.denied) {
      return [
        FilledButton(
          onPressed: onRetry,
          child: Text(l10n.addUpAudioPermissionRetry),
        ),
      ];
    }
    if (state.permission == UpAudioPermissionState.permanentlyDenied) {
      return [
        FilledButton(
          onPressed: onOpenSettings,
          child: Text(l10n.addUpAudioOpenSettings),
        ),
      ];
    }
    return const [];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textStrong,
            ),
          ),
        ),
        if (trailing != null)
          Expanded(
            child: Text(
              trailing!,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({this.onCrisi, this.onSave, this.saving = false});
  final VoidCallback? onCrisi;
  final VoidCallback? onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
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
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: onCrisi,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.warningLight,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.warning),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.heart_broken_outlined,
                          size: 20,
                          color: c.warningInk,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.addUpCrisi,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: c.warningInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: AppButton(
                  label: l10n.addUpSave,
                  onPressed: onSave,
                  loading: saving,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
