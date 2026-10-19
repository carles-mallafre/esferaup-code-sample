import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/startup/app_startup.dart';
import 'package:esferaup/core/storage/device_secure_store.dart';
import 'package:esferaup/core/startup/pending_session_recovery.dart';
import 'package:esferaup/core/theme/app_colors.dart';
import 'package:esferaup/core/theme/app_spacing.dart';
import 'package:esferaup/core/widgets/buttons/app_button.dart';
import 'package:esferaup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

Uri keychainHelpUri(Locale locale) {
  final code = switch (locale.languageCode) {
    'ca' || 'es' => locale.languageCode,
    _ => 'en',
  };
  return Uri.parse('${Env.webBaseUrl}/$code/ajuda/clauer');
}

/// Fail-closed startup boundary for unavailable secure storage or an ambiguous
/// receipt-backed workspace switch. Retry re-runs the gated startup sequence.
class StorageBlockedScreen extends ConsumerWidget {
  const StorageBlockedScreen({super.key, this.onRetry, this.error});

  final VoidCallback? onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final failure = error ?? ref.watch(appStartupProvider).error;
    final recoveryPending = failure is PendingSessionRecoveryUnavailable;
    final storageUnavailable = failure is SecureStorageUnavailable;
    return Scaffold(
      backgroundColor: c.surfaceCanvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  recoveryPending
                      ? Icons.wifi_off_rounded
                      : storageUnavailable
                      ? Icons.lock_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 56,
                  color: c.error,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  recoveryPending
                      ? l10n.familyInviteNetworkTitle
                      : storageUnavailable
                      ? l10n.storageBlockedTitle
                      : l10n.startupUnavailableTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.textStrong,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                Text(
                  recoveryPending
                      ? l10n.activaLookupOffline
                      : storageUnavailable
                      ? l10n.storageBlockedBody
                      : l10n.startupUnavailableBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.s5),
                AppButton(
                  label: l10n.commonRetry,
                  fullWidth: false,
                  onPressed:
                      onRetry ?? () => ref.invalidate(appStartupProvider),
                ),
                if (storageUnavailable) ...[
                  const SizedBox(height: AppSpacing.s3),
                  TextButton(
                    onPressed: () => launchUrl(
                      keychainHelpUri(Localizations.localeOf(context)),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      l10n.storageBlockedHelp,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
