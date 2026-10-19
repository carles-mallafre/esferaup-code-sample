import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/bottom_action_bar.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/chips/app_chip.dart';
import 'package:esferaup/core/widgets/inputs/app_text_field.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';
import 'package:esferaup/features/up/domain/up_tag.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/widgets/mood_selector.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpEditScreen extends ConsumerStatefulWidget {
  const UpEditScreen({super.key, required this.detail});
  final UpDetail detail;

  @override
  ConsumerState<UpEditScreen> createState() => _UpEditScreenState();
}

class _UpEditScreenState extends ConsumerState<UpEditScreen> {
  late final _note = TextEditingController(text: widget.detail.note);
  late final _tag = TextEditingController(text: widget.detail.tag);
  late String _category = widget.detail.category;
  late UpMood? _mood = widget.detail.mood;
  bool _saving = false;
  bool _tagInvalid = false;

  @override
  void dispose() {
    _note.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!validUpTag(_tag.text)) {
      setState(() => _tagInvalid = true);
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(upRepositoryProvider)
          .updateUp(
            upId: widget.detail.id,
            category: _category,
            mood: _mood,
            note: _note.text,
            tag: _tag.text,
          );
      if (!mounted) return;
      invalidateUpReads(ref, widget.detail.profileId);
      ref.invalidate(upDetailControllerProvider(widget.detail.id));
      Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.upEditFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.colors.surfaceCanvas,
      appBar: AppHeader(title: l10n.upEditTitle, centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            MaterialLocalizations.of(
              context,
            ).formatFullDate(widget.detail.occurredAt),
            style: TextStyle(color: context.colors.textMuted),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.addUpMoodTitle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          MoodSelector(
            selected: _mood,
            onChanged: (mood) => setState(() => _mood = mood),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.addUpCategory,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
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
                  label: upCategoryLabel(l10n, category),
                  selected: _category == category,
                  onTap: widget.detail.categoryEditable
                      ? () => setState(() => _category = category)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 24),
          AppTextField(
            controller: _note,
            label: l10n.addUpNoteTitle,
            maxLines: 5,
            inputFormatters: [LengthLimitingTextInputFormatter(8000)],
          ),
          const SizedBox(height: 24),
          AppTextField(
            controller: _tag,
            key: const ValueKey('up-edit-tag'),
            label: l10n.upTagTitle,
            hint: l10n.upTagHint,
            autocorrect: false,
            errorText: _tagInvalid ? l10n.upTagInvalid : null,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            onChanged: (_) {
              if (_tagInvalid) setState(() => _tagInvalid = false);
            },
          ),
          const SizedBox(height: 8),
          Text(
            l10n.upTagHelp,
            style: TextStyle(fontSize: 12, color: context.colors.textMuted),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: AppButton(
          label: l10n.upEditSave,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
    );
  }
}
