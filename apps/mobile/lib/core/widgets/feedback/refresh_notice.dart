import 'package:esferaup/core/widgets/feedback/app_snack_bar.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Pull-to-refresh body: when the reload fails the screen keeps what it showed
/// and an error snack bar (announced by screen readers) says it did not refresh.
Future<void> refreshOrNotify(
  BuildContext context,
  Future<void> Function() reload,
) async {
  try {
    await reload();
  } on Exception {
    if (context.mounted) {
      showErrorSnackBar(
        context,
        AppLocalizations.of(context).commonRefreshFailed,
      );
    }
  }
}
