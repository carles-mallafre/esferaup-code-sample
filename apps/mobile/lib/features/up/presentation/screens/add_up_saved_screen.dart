import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/core/widgets/navigation/app_header.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:esferaup/features/home/presentation/providers/home_action_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';

class AddUpSavedArgs {
  const AddUpSavedArgs({required this.upId, required this.esfera});

  final String upId;
  final String esfera;
}

/// `Add UP · Guardat` (§6). Confirmation after saving a UP: a success hero, the
/// daily-reminder nudge, and next actions. The esfera name is the saved UP's
/// category.
class AddUpSavedScreen extends ConsumerStatefulWidget {
  const AddUpSavedScreen({
    super.key,
    this.upId,
    this.esfera,
    this.onBack,
    this.onActivateReminder,
    this.onReminderLater,
    this.onViewUp,
    this.onAddAnother,
  });

  final String? esfera;
  final String? upId;
  final VoidCallback? onBack;
  final VoidCallback? onActivateReminder;
  final VoidCallback? onReminderLater;
  final VoidCallback? onViewUp;
  final VoidCallback? onAddAnother;

  @override
  ConsumerState<AddUpSavedScreen> createState() => _AddUpSavedScreenState();
}

class _AddUpSavedScreenState extends ConsumerState<AddUpSavedScreen> {
  bool _reminderDismissed = false;

  @override
  void didUpdateWidget(covariant AddUpSavedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upId != widget.upId) _reminderDismissed = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final detail = widget.upId == null
        ? null
        : ref.watch(upDetailControllerProvider(widget.upId!)).valueOrNull;
    final sphere = detail == null
        ? widget.esfera
        : upCategoryLabel(l10n, detail.category);
    final reminder = detail == null
        ? null
        : ref.watch(recordatoriProvider(detail.profileId)).valueOrNull;
    final showReminder =
        !_reminderDismissed &&
        (widget.upId == null || reminder?.enabled == false);
    return Scaffold(
      backgroundColor: c.surfaceCanvas,
      appBar: AppHeader(onBack: widget.onBack),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s5,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight - AppSpacing.s3 - AppSpacing.s5,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    _HeroCard(
                      title: l10n.addUpSavedTitle,
                      body: sphere == null
                          ? l10n.addUpSavedGenericBody
                          : l10n.addUpSavedBody(sphere),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    if (showReminder)
                      _ReminderCard(
                        onActivate: widget.onActivateReminder,
                        onLater: widget.onReminderLater == null
                            ? null
                            : () {
                                setState(() => _reminderDismissed = true);
                                widget.onReminderLater!();
                              },
                      ),
                    const Spacer(),
                    AppButton(
                      label: l10n.addUpSavedViewUp,
                      variant: AppButtonVariant.secondary,
                      onPressed: widget.onViewUp,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    AppButton(
                      label: l10n.addUpSavedAddAnother,
                      onPressed: widget.onAddAnother,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        color: c.surfaceFeature,
        child: Stack(
          children: [
            Positioned(
              top: -40,
              left: 230,
              child: _circle(180, c.accent.withValues(alpha: 0.14)),
            ),
            Positioned(
              top: 120,
              left: 250,
              child: _circle(140, c.accent.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.success,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 44,
                      color: c.textOnLight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s5),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: c.textOnFeature,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: c.textOnFeature,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double d, Color color) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({this.onActivate, this.onLater});
  final VoidCallback? onActivate;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: c.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: c.primary,
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  l10n.addUpSavedReminderTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            l10n.addUpSavedReminderBody,
            style: TextStyle(fontSize: 13, height: 1.45, color: c.textMuted),
          ),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s2,
              children: [
                TextButton(
                  onPressed: onLater,
                  child: Text(
                    l10n.addUpSavedReminderLater,
                    style: TextStyle(
                      color: c.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppButton(
                  label: l10n.addUpSavedReminderActivate,
                  size: AppButtonSize.small,
                  fullWidth: false,
                  onPressed: onActivate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
