import 'dart:async';

import 'package:dio/dio.dart';
import 'package:esferaup/core/errors/app_error.dart';
import 'package:esferaup/core/errors/error_mapper.dart';
import 'package:esferaup/core/network/secure_token_store.dart';
import 'package:esferaup/core/network/session.dart';
import 'package:esferaup/core/network/token_refresher.dart';
import 'package:esferaup/core/utils/app_logger.dart';

const skipAuthRefreshRetryExtra = 'skipAuthRefreshRetry';

/// Attaches the bearer token and performs **single-flight** token refresh
/// (proactive + reactive). One instance holds the in-flight refresh completer
/// so there is never more than one `POST /v1/auth/refresh` at a time;
/// concurrent 401s await the same refresh and replay. A *network*-failed
/// refresh never logs the user out; a server-*rejected* refresh does.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.store,
    required this.refresher,
    required this.onExpired,
    this.terminateSession,
  });

  final SecureTokenStore store;
  final TokenRefresher Function() refresher;
  final void Function(SessionExpiredReason) onExpired;
  final Future<bool> Function({
    required int? storeGeneration,
    required SessionExpiredReason reason,
  })?
  terminateSession;

  static const _buffer = Duration(minutes: 5);
  static const _proactiveTimeout = Duration(seconds: 12);
  static const _retriedFlag = 'x-auth-retried';
  static const _originGenerationKey = 'x-auth-origin-generation';
  static const _authAttachedKey = 'x-auth-attached';

  Completer<TokenPair?>? _refreshing;
  int? _refreshGeneration;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.extra[_originGenerationKey] = null;
    options.extra[_authAttachedKey] = false;
    if (options.extra['skipAuth'] == true) return handler.next(options);

    // Dio retries reuse RequestOptions. Never let a header attached before a
    // tenant transition survive a retry whose secure-session read is blocked.
    options.headers.remove('Authorization');

    TokenPairSnapshot? snapshot;
    try {
      snapshot = await store.readSnapshot();
    } on SecureStorageUnavailable {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: const NetworkError(debugMessage: 'secure storage'),
          type: DioExceptionType.unknown,
        ),
        true,
      );
    }

    var pair = snapshot?.pair;
    if (pair != null && pair.expiresWithin(_buffer)) {
      // Proactive refresh, but never hang the request forever.
      pair =
          await _ensureRefreshed(
                pair.refreshToken,
                generation: snapshot!.generation,
              )
              .timeout(_proactiveTimeout, onTimeout: () => pair)
              .catchError((_) => pair);
    }

    if (pair != null &&
        snapshot != null &&
        store.isGenerationCurrent(snapshot.generation)) {
      options.headers['Authorization'] = 'Bearer ${pair.accessToken}';
      options.extra[_originGenerationKey] = snapshot.generation;
      options.extra[_authAttachedKey] = true;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final isRetryable =
        status == 401 &&
        err.requestOptions.extra[_retriedFlag] != true &&
        err.requestOptions.extra[skipAuthRefreshRetryExtra] != true;
    if (!isRetryable) return handler.next(err);

    final authAttached = err.requestOptions.extra[_authAttachedKey] == true;
    final originGeneration =
        err.requestOptions.extra[_originGenerationKey] as int?;
    if (!authAttached ||
        originGeneration == null ||
        !store.isGenerationCurrent(originGeneration)) {
      AppLogger.warn(
        'auth refresh skipped: attached=$authAttached '
        'generation=$originGeneration current=${originGeneration != null && store.isGenerationCurrent(originGeneration)}',
      );
      return handler.next(err);
    }

    TokenPairSnapshot? snapshot;
    try {
      snapshot = await store.readSnapshot();
    } on SecureStorageUnavailable {
      return handler.next(err);
    }
    if (snapshot == null || snapshot.generation != originGeneration) {
      AppLogger.warn('auth refresh skipped: session changed or unreadable');
      return handler.next(err);
    }
    final originalError = dioErrorToAppError(err);
    final receiptRecoverableRevocation =
        originalError is AuthError && originalError.code == 'SESSION_REVOKED';
    if (originalError is AuthError &&
        originalError.hardLogout &&
        !receiptRecoverableRevocation) {
      await _terminate(originGeneration, _reasonFor(originalError));
      return handler.next(err);
    }

    final TokenPair? refreshed;
    try {
      refreshed = await _ensureRefreshed(
        snapshot.pair.refreshToken,
        generation: originGeneration,
      );
    } on AuthError catch (error) {
      await _terminate(
        originGeneration,
        receiptRecoverableRevocation
            ? _reasonFor(originalError)
            : _reasonFor(error),
      );
      return handler.next(err);
    } on NetworkError catch (error) {
      AppLogger.warn('auth refresh failed: $error');
      // Transient — keep tokens, surface a connectivity error.
      return handler.next(err);
    } on ServerError catch (error) {
      AppLogger.warn('auth refresh failed: $error');
      return handler.next(err);
    } on RateLimitError catch (error) {
      AppLogger.warn('auth refresh failed: $error');
      return handler.next(err);
    } on AppError catch (error) {
      AppLogger.warn('auth refresh failed: $error');
      if (receiptRecoverableRevocation) {
        await _terminate(originGeneration, _reasonFor(originalError));
      }
      return handler.next(err);
    } catch (error) {
      AppLogger.warn('auth refresh failed: ${error.runtimeType}');
      return handler.next(err);
    }
    if (refreshed == null || !store.isGenerationCurrent(originGeneration)) {
      AppLogger.warn('auth refresh produced no usable session');
      return handler.next(err);
    }

    // Replay the original request once with the new token, via a bare Dio.
    final req = err.requestOptions
      ..headers['Authorization'] = 'Bearer ${refreshed.accessToken}'
      ..extra[_retriedFlag] = true;
    try {
      final response = await Dio(
        BaseOptions(baseUrl: req.baseUrl),
      ).fetch<dynamic>(req);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<bool> _terminate(
    int? storeGeneration,
    SessionExpiredReason reason,
  ) async {
    final terminator = terminateSession;
    if (terminator != null) {
      return terminator(storeGeneration: storeGeneration, reason: reason);
    }
    final cleared = storeGeneration == null
        ? await _clearMissingSession()
        : await store.clearIfCurrent(generation: storeGeneration);
    if (cleared) onExpired(reason);
    return cleared;
  }

  Future<bool> _clearMissingSession() async {
    await store.clear();
    return true;
  }

  static SessionExpiredReason _reasonFor(AuthError error) {
    if (error.code == 'ROLE_CHANGED') return SessionExpiredReason.roleChanged;
    if (error.code == 'TOKEN_INVALIDATED' || error.code == 'SESSION_REVOKED') {
      return SessionExpiredReason.revoked;
    }
    return SessionExpiredReason.expired;
  }

  /// Single-flight refresh. Returns the fresh pair (also persisted), or rethrows
  /// [AuthError] (server rejection → logout) / [NetworkError] (transient → keep).
  Future<TokenPair?> _ensureRefreshed(
    String refreshToken, {
    required int generation,
  }) {
    final existing = _refreshing;
    if (existing != null) {
      if (_refreshGeneration == generation) return existing.future;
      return Future.value();
    }

    final completer = Completer<TokenPair?>();
    _refreshing = completer;
    _refreshGeneration = generation;
    () async {
      try {
        final pair = await refresher().refresh(refreshToken);
        final persisted = await store.writeIfCurrent(
          pair,
          generation: generation,
        );
        if (!persisted) {
          completer.complete();
          return;
        }
        AppLogger.info('token refreshed');
        completer.complete(pair);
      } on DioException catch (e) {
        completer.completeError(dioErrorToAppError(e));
      } catch (e) {
        completer.completeError(
          e is AppError ? e : UnknownError(debugMessage: e.toString()),
        );
      } finally {
        if (identical(_refreshing, completer)) {
          _refreshing = null;
          _refreshGeneration = null;
        }
      }
    }();
    return completer.future;
  }
}
