import 'dart:async';

import 'package:esferaup/core/network/secure_token_store.dart';

/// [noSession] is the startup cleanup when no session was stored: there is no
/// account to tear down, so a capability that opened the app (an invitation, a
/// migration link) must survive it for the sign-in that follows.
enum SessionTransitionKind { replacement, logout, rejected, noSession }

class SessionTransitionSuperseded implements Exception {
  const SessionTransitionSuperseded();
}

typedef SessionTransitionHook =
    Future<void> Function(SessionTransitionKind kind);

/// Owns the security boundary between authenticated sessions on a shared device.
///
/// Local tenant-scoped artifacts are made inaccessible before a new token pair
/// is published. Every flow that changes account or tenant must use this class.
class SessionTransitionCoordinator {
  SessionTransitionCoordinator({
    required SecureTokenStore tokenStore,
    SessionTransitionHook? onSessionStopping,
    Future<void> Function()? onLocalClear,
    void Function()? onSessionReset,
    Future<void> Function()? onSessionReady,
    Future<void> Function()? onSessionCommitted,
  }) : _tokenStore = tokenStore,
       _onSessionStopping = onSessionStopping,
       _onLocalClear = onLocalClear,
       _onSessionReset = onSessionReset,
       _onSessionReady = onSessionReady,
       _onSessionCommitted = onSessionCommitted;

  final SecureTokenStore _tokenStore;
  final SessionTransitionHook? _onSessionStopping;
  final Future<void> Function()? _onLocalClear;
  final void Function()? _onSessionReset;
  final Future<void> Function()? _onSessionReady;
  final Future<void> Function()? _onSessionCommitted;
  Future<void> _operationTail = Future<void>.value();
  int _transitionGeneration = 0;

  Future<void> replace(TokenPair pair) async {
    // Reserve the secure-store generation synchronously. A refresh or hard
    // rejection from the previous tenant can no longer win while this
    // transition is waiting behind another local cleanup operation.
    final storeGeneration = _tokenStore.beginSessionTransition();
    final transitionGeneration = ++_transitionGeneration;
    await _serialized(() async {
      _assertCurrent(transitionGeneration);
      try {
        // The old slot remains crash-recoverable while in-process reads are
        // blocked. A process death before the atomic target-slot flip can replay
        // the server receipt with the still-complete source refresh token.
        await _drainAndClear(
          SessionTransitionKind.replacement,
          transitionGeneration,
        );
        final persisted = await _tokenStore.writeIfCurrent(
          pair,
          generation: storeGeneration,
        );
        if (!persisted) throw const SessionTransitionSuperseded();
      } on Object catch (error, stackTrace) {
        try {
          await _tokenStore.clearStorageIfCurrent(generation: storeGeneration);
        } on Object {
          // Reads remain blocked for this process. A fresh process can still
          // recover the complete source slot and its digest-bound receipt.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }

      try {
        _assertCurrent(transitionGeneration);
        await _onSessionReady?.call();
        _assertCurrent(transitionGeneration);
        await _onSessionCommitted?.call();
      } on Object {
        final cleared = await _tokenStore.clearStorageIfCurrent(
          generation: storeGeneration,
        );
        if (cleared) {
          try {
            await _drainAndClear(
              SessionTransitionKind.rejected,
              transitionGeneration,
            );
          } on Object {
            // Preserve the original readiness/commit failure. Credentials are
            // already absent and every rollback hook was still attempted.
          }
        }
        rethrow;
      }
    });
  }

  Future<TokenPair?> takeAndClear() async {
    // Invalidate in-flight refreshes at invocation time, not when this work
    // eventually reaches the coordinator queue. A request that starts after
    // the user taps logout must never be allowed to republish the old pair.
    final pairFuture = _tokenStore.takeAndClear();
    final transitionGeneration = ++_transitionGeneration;
    return _serialized(() async {
      final pair = await pairFuture;
      _assertCurrent(transitionGeneration);
      await _drainAndClear(SessionTransitionKind.logout, transitionGeneration);
      return pair;
    });
  }

  /// Completes a hard server-driven logout only if the rejected request still
  /// belongs to the current secure session. A late 401 from family A cannot
  /// erase a newly installed family B session.
  Future<bool> rejectIfCurrent({required int storeGeneration}) async {
    if (!_tokenStore.isGenerationCurrent(storeGeneration)) return false;
    final transitionGeneration = ++_transitionGeneration;
    // `clearIfCurrent` advances the secure-session generation synchronously.
    // Queue the physical delete now so a refresh cannot resurrect this session
    // while another coordinator cleanup is draining.
    final clearFuture = _tokenStore.clearIfCurrent(generation: storeGeneration);
    return _serialized(() async {
      final cleared = await clearFuture;
      if (!cleared) return false;
      try {
        _assertCurrent(transitionGeneration);
        await _drainAndClear(
          SessionTransitionKind.rejected,
          transitionGeneration,
        );
        return true;
      } on SessionTransitionSuperseded {
        // The newer transition owns the same mandatory cleanup sequence.
        return false;
      }
    });
  }

  /// Clears an already missing/corrupt session and every tenant-scoped local
  /// artifact. Used by recovery and debug environment changes.
  Future<void> clear() async {
    // See [takeAndClear]: session invalidation is synchronous even if artifact
    // cleanup has to wait for an earlier transition to finish.
    final clearFuture = _tokenStore.clear();
    final transitionGeneration = ++_transitionGeneration;
    await _serialized(() async {
      await clearFuture;
      _assertCurrent(transitionGeneration);
      await _drainAndClear(SessionTransitionKind.logout, transitionGeneration);
    });
  }

  /// [clear] for a start without any stored session.
  Future<void> clearMissing() async {
    final clearFuture = _tokenStore.clear();
    final transitionGeneration = ++_transitionGeneration;
    await _serialized(() async {
      await clearFuture;
      _assertCurrent(transitionGeneration);
      await _drainAndClear(
        SessionTransitionKind.noSession,
        transitionGeneration,
      );
    });
  }

  Future<void> _drainAndClear(
    SessionTransitionKind kind,
    int expectedGeneration,
  ) async {
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _onSessionStopping?.call(kind);
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStack = stackTrace;
    }
    _assertCurrent(expectedGeneration);
    try {
      _onSessionReset?.call();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    try {
      await _onLocalClear?.call();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
    _assertCurrent(expectedGeneration);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  void _assertCurrent(int expectedGeneration) {
    if (expectedGeneration != _transitionGeneration) {
      throw const SessionTransitionSuperseded();
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
