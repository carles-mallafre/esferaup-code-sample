import 'package:dio/dio.dart';
import 'package:esferaup/core/config/api_environment.dart';
import 'package:esferaup/core/config/env.dart';
import 'package:esferaup/core/network/auth_interceptor.dart';
import 'package:esferaup/core/network/interceptors.dart';
import 'package:esferaup/core/network/policy_reacceptance_gate.dart';
import 'package:esferaup/core/network/profile_write_block_gate.dart';
import 'package:esferaup/core/network/request_deadline.dart';
import 'package:esferaup/core/network/secure_token_store.dart';
import 'package:esferaup/core/network/session.dart';
import 'package:esferaup/core/network/token_refresher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_client.g.dart';

typedef SessionTerminator =
    Future<bool> Function({
      required int? storeGeneration,
      required SessionExpiredReason reason,
    });

@Riverpod(keepAlive: true)
SecureTokenStore secureTokenStore(Ref ref) => SecureTokenStore();

/// Core fallback used outside the application root (background/unit harnesses).
/// The production container overrides this with the full artifact coordinator.
@Riverpod(keepAlive: true)
SessionTerminator sessionTerminator(Ref ref) {
  final store = ref.watch(secureTokenStoreProvider);
  return ({required storeGeneration, required reason}) async {
    final cleared = storeGeneration == null
        ? await _clearStore(store)
        : await store.clearIfCurrent(generation: storeGeneration);
    if (cleared) {
      ref.read(sessionControllerProvider.notifier).expire(reason);
    }
    return cleared;
  };
}

@Riverpod(keepAlive: true)
ETagCacheInterceptor etagCacheInterceptor(Ref ref) => ETagCacheInterceptor();

Future<bool> _clearStore(SecureTokenStore store) async {
  await store.clear();
  return true;
}

BaseOptions _baseOptions(String baseUrl) => BaseOptions(
  baseUrl: baseUrl,
  connectTimeout: Env.connectTimeout,
  receiveTimeout: Env.receiveTimeout,
  contentType: 'application/json',
  headers: {'Accept': 'application/json'},
  validateStatus: (s) => s != null && s >= 200 && s < 300,
);

/// The app's single Dio. Interceptor order:
/// RequestDeadline → Auth → CorrelationId → Idempotency → PolicyReacceptance → ProfileWriteBlock
/// → Retry → ETagCache → (debug) NetworkLog.
/// The logger runs last so it traces the fully-decorated request + the final
/// outcome. Background isolates use [backgroundDio] instead.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  // Watch the runtime environment so a debug env switch rebuilds the client (and
  // everything that depends on it) against the new base URL.
  final env = ref.watch(apiEnvironmentProvider);
  final dio = Dio(_baseOptions(Env.baseUrlFor(env)));
  dio.httpClientAdapter = DeadlineHttpClientAdapter(dio.httpClientAdapter);
  final store = ref.watch(secureTokenStoreProvider);
  dio.interceptors.addAll([
    RequestDeadlineInterceptor(),
    AuthInterceptor(
      store: store,
      refresher: () => ref.read(tokenRefresherProvider),
      onExpired: (reason) =>
          ref.read(sessionControllerProvider.notifier).expire(reason),
      terminateSession: ref.watch(sessionTerminatorProvider),
    ),
    CorrelationIdInterceptor(),
    IdempotencyInterceptor(),
    PolicyReacceptanceInterceptor(
      (versions) => ref
          .read(policyReacceptanceControllerProvider.notifier)
          .requireReacceptance(versions),
    ),
    ProfileWriteBlockInterceptor(
      (reason, profileId) => ref
          .read(profileWriteBlockProvider.notifier)
          .report(reason, profileId: profileId),
    ),
    RetryInterceptor(dio),
    ref.watch(etagCacheInterceptorProvider),
    if (kDebugMode) const NetworkLogInterceptor(),
  ]);
  return dio;
}

/// A standalone Dio for workmanager background isolates: it attaches the
/// current token but has NO session-expired callback — on auth failure a
/// background task aborts + reschedules rather than triggering app re-auth.
Future<Dio> backgroundDio() async {
  // Background isolates have no provider container — they use the build-time env.
  final dio = Dio(_baseOptions(Env.apiBaseUrl));
  final store = SecureTokenStore();
  dio.interceptors.addAll([
    CorrelationIdInterceptor(),
    IdempotencyInterceptor(),
  ]);
  final pair = await store.read();
  if (pair != null) {
    dio.options.headers['Authorization'] = 'Bearer ${pair.accessToken}';
  }
  return dio;
}
