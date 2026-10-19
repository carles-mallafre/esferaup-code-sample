import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/features/feed/presentation/providers/invalidate_up_reads.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/presentation/localization/up_localizations.dart';
import 'package:esferaup/features/up/presentation/providers/up_providers.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirms a delete and offers to undo it. The detail screen is gone by the
/// time the action is tapped, so this holds the messenger and the provider
/// container instead of that screen's context and ref.
void showUpDeletedSnackBar({
  required ScaffoldMessengerState messenger,
  required ProviderContainer container,
  required AppLocalizations l10n,
  required String upId,
  required String profileId,
}) {
  void say(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        persist: false,
        content: Text(l10n.upDeletedSnack(upRecoveryDays)),
        action: SnackBarAction(
          label: l10n.upDeletedUndo,
          onPressed: () async {
            try {
              await container.read(upRepositoryProvider).restoreUp(upId);
              invalidateUpReadsIn(container, profileId);
              container
                ..invalidate(deletedUpsProvider(profileId))
                ..invalidate(upDetailControllerProvider(upId));
              say(l10n.upRestored);
            } on AppError catch (e) {
              final block = UpRestoreBlock.fromErrorCode(e.code);
              say(
                block != null
                    ? upRestoreBlockMessage(l10n, block)
                    : l10n.upRestoreFailed,
              );
            } on Object {
              say(l10n.upRestoreFailed);
            }
          },
        ),
      ),
    );
}
