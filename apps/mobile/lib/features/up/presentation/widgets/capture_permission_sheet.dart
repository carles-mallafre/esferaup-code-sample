import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<bool?> showCapturePermissionSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.colors.surfaceCard,
  builder: (context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: context.colors.primaryLight,
            child: Icon(icon, color: context.colors.primary, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: context.colors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: AppLocalizations.of(context).addUpAudioPermissionContinue,
            onPressed: () => Navigator.pop(context, true),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).addUpAudioPermissionLater),
          ),
        ],
      ),
    ),
  ),
);
