import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Title and explanation for a write a profile refused: what happened, that
/// reading still works, and what unblocks it.
({String title, String body}) profileWriteBlockCopy(
  AppLocalizations l10n,
  ProfileWriteBlock reason,
) => switch (reason) {
  ProfileWriteBlock.handoffInProgress => (
    title: l10n.writeBlockHandoffTitle,
    body: l10n.writeBlockHandoffBody,
  ),
  ProfileWriteBlock.awaitingAdultConsent => (
    title: l10n.writeBlockAwaitingTitle,
    body: l10n.writeBlockAwaitingBody,
  ),
  ProfileWriteBlock.erasureRequested => (
    title: l10n.writeBlockErasedTitle,
    body: l10n.writeBlockErasedBody,
  ),
};

/// The same explanation for a surface that shows its own inline error: null
/// when [error] is not a refused profile write.
String? profileWriteBlockMessage(AppLocalizations l10n, Object? error) =>
    error is MigrationLockedError
    ? profileWriteBlockCopy(l10n, error.reason).body
    : null;

bool _showing = false;

/// Explains one refused write. A second refusal while the explanation is open
/// does not stack another dialog.
Future<void> showProfileWriteBlockDialog(
  BuildContext context,
  ProfileWriteBlock reason, {
  VoidCallback? onSeeHandoffStatus,
}) async {
  if (_showing) return;
  _showing = true;
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        final copy = profileWriteBlockCopy(l10n, reason);
        return AlertDialog(
          scrollable: true,
          title: Text(copy.title),
          content: Text(copy.body),
          actions: [
            if (reason == ProfileWriteBlock.handoffInProgress &&
                onSeeHandoffStatus != null)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  onSeeHandoffStatus();
                },
                child: Text(l10n.writeBlockSeeStatus),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.writeBlockOk),
            ),
          ],
        );
      },
    );
  } finally {
    _showing = false;
  }
}
