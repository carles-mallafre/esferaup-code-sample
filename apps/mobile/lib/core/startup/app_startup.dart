import 'package:esferaup/core/config/api_environment.dart';
import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/network/dio_client.dart';
import 'package:esferaup/core/network/secure_token_store.dart';
import 'package:esferaup/core/network/session.dart';
import 'package:esferaup/core/network/session_backend.dart';
import 'package:esferaup/core/startup/pending_session_recovery.dart';
import 'package:esferaup/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_startup.g.dart';

typedef NoSessionCleanup = Future<void> Function();
typedef AuthenticatedSessionStartup = Future<void> Function();

/// Application-root override removes tenant artifacts when secure storage has
/// no authenticated session. The no-op fallback keeps isolated test harnesses
/// independent from feature-layer providers.
@Riverpod(keepAlive: true)
NoSessionCleanup noSessionCleanup(Ref ref) => () async {};

/// Feature-layer override replays a persisted tenant-switch receipt before the
/// old source session becomes visible after a process restart.
@Riverpod(keepAlive: true)
PendingSessionRecovery pendingSessionRecovery(Ref ref) =>
    (_) async => PendingSessionRecoveryResult.none;

/// Application-root hook resumes account-bound workers only after startup has
/// recovered any pending tenant replacement and re-read the authoritative pair.
@Riverpod(keepAlive: true)
AuthenticatedSessionStartup authenticatedSessionStartup(Ref ref) => () async {};

/// Gated startup sequence (§8). Restores the session from fail-closed secure
/// storage and seeds [SessionController]; the router shows the Splash while this
/// resolves. Force-update / remote-flags steps are layered in as those features
/// land.
@Riverpod(keepAlive: true)
class AppStartup extends _$AppStartup {
  @override
  Future<void> build() async {
    final store = ref.watch(secureTokenStoreProvider);
    final session = ref.read(sessionControllerProvider.notifier);

    try {
      await store.ensureAvailable();
      var pair = await store.read();
      final baseUrl = Env.baseUrlFor(ref.read(apiEnvironmentProvider));
      final backend = ref.read(sessionBackendBindingProvider);
      if (pair != null && !backend.matches(baseUrl, strict: kDebugMode)) {
        AppLogger.warn('Stored session belongs to another API; signing out');
        await store.clear();
        pair = null;
      }
      if (pair == null) {
        await ref.read(noSessionCleanupProvider)();
        session.expire(SessionExpiredReason.unauthenticated);
      } else {
        final recovery = await ref.read(pendingSessionRecoveryProvider)(pair);
        if (recovery == PendingSessionRecoveryResult.transportPending) {
          // The server may already have revoked the source lineage and committed
          // the target switch. Keep auth unknown so no source-bound provider or
          // worker can issue a request that destroys the recoverable receipt.
          throw const PendingSessionRecoveryUnavailable();
        }
        pair = await store.read();
        if (pair == null) {
          // An authoritative recovery rejection already crossed the full
          // teardown boundary; do not run it a second time.
          session.expire(SessionExpiredReason.unauthenticated);
        } else {
          if (recovery != PendingSessionRecoveryResult.recovered) {
            await ref.read(authenticatedSessionStartupProvider)();
          }
          await backend.bind(baseUrl);
          session.markAuthenticated();
        }
      }
    } on SecureStorageUnavailable catch (e) {
      // Fail-closed (§7.1 — 091-WP12): the device keychain is unavailable. We
      // cannot safely hold tokens, so the app REFUSES to operate — the router
      // shows StorageBlockedScreen (never a plaintext fallback, never a silent
      // signed-out loop). Retry re-runs this provider.
      AppLogger.error('Secure storage unavailable at startup', e);
      rethrow;
    } on Object catch (error, stack) {
      AppLogger.error(
        'App startup failed (${error.runtimeType})',
        error,
        stack,
      );
      rethrow;
    }
  }
}
