import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:esferaup/core/network/request_deadline.dart';
import 'package:esferaup/core/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _mutationMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};
const skipMutationRetryExtra = 'skipMutationRetry';

/// Sets `X-Request-ID` per request so a mobile error correlates with the
/// backend log line / Sentry event. Reused on retries of the same options.
class CorrelationIdInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.putIfAbsent('X-Request-ID', () => _uuid.v4());
    handler.next(options);
  }
}

/// Adds a mandatory `Idempotency-Key` to API mutations. For retryable mutations
/// the caller supplies a STABLE key via `options.extra['idempotencyKey']`
/// (generated once when the command/draft is created) so a network retry never
/// double-creates. Otherwise a fresh v4 is minted per call.
class IdempotencyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    if (_mutationMethods.contains(method) &&
        options.extra[skipMutationRetryExtra] != true) {
      final stable = options.extra['idempotencyKey'] as String?;
      options.headers.putIfAbsent(
        'Idempotency-Key',
        () => stable ?? _uuid.v4(),
      );
    }
    handler.next(options);
  }
}

/// Retries transient transport failures. Idempotent GETs retry up to [maxGet]×;
/// Mutations retry only when carrying a stable `Idempotency-Key` (safe to
/// replay). Jittered exponential backoff, and never past the request deadline.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxGet = 2});

  final Dio _dio;
  final int maxGet;
  static const _attemptKey = 'x-retry-attempt';
  final _rng = Random();

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_isTransient(err)) return handler.next(err);

    final options = err.requestOptions;
    if (options.extra[skipMutationRetryExtra] == true) {
      return handler.next(err);
    }
    final method = options.method.toUpperCase();
    final replayable =
        method == 'GET' ||
        (_mutationMethods.contains(method) &&
            options.headers.containsKey('Idempotency-Key'));
    if (!replayable) return handler.next(err);

    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= maxGet) return handler.next(err);

    final backoff = Duration(
      milliseconds: (200 * pow(2, attempt)).toInt() + _rng.nextInt(150),
    );
    final left = requestTimeLeft(options);
    if (left != null && left <= backoff) return handler.next(err);
    await Future<void>.delayed(backoff);
    options.extra[_attemptKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _isTransient(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.badResponse:
        final s = err.response?.statusCode ?? 0;
        return s >= 502 && s <= 504;
      case DioExceptionType.unknown:
        // A reused keep-alive socket the server already closed surfaces here
        // ("Connection closed before full header was received").
        final cause = err.error;
        return cause is HttpException || cause is SocketException;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }
}

/// Conditional-GET cache (HTTP ETag / `If-None-Match`). On a cacheable GET it
/// replays the stored `ETag`; the server answers `304 Not Modified` (no body)
/// when nothing changed, and this interceptor serves the cached response — so a
/// re-fetch of unchanged content (e.g. an Activa plan whose `content_version`
/// hasn't bumped) costs ~0 bytes. Opt out per-request with
/// `options.extra['etagCache'] = false`.
///
/// Note: the Dio client's `validateStatus` treats 304 as an error, so the 304
/// arrives via [onError]; we resolve it with the cached payload there.
class ETagCacheInterceptor extends Interceptor {
  ETagCacheInterceptor({this.maxEntries = 128});

  final int maxEntries;
  // Insertion-ordered → cheap LRU-ish eviction of the oldest entry.
  final _cache = <String, _ETagEntry>{};
  int _generation = 0;

  static const _generationKey = 'etag-session-generation';
  static String _key(RequestOptions o) => '${o.method.toUpperCase()} ${o.uri}';
  static bool _enabled(RequestOptions o) =>
      o.method.toUpperCase() == 'GET' && o.extra['etagCache'] != false;

  /// Session/tenant replacements must not let a 304 response reuse another
  /// family's cached body, even when both tenants share the same request URI.
  void clear() {
    _generation++;
    _cache.clear();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_enabled(options)) {
      options.extra[_generationKey] = _generation;
      final hit = _cache[_key(options)];
      if (hit != null) {
        options.headers.putIfAbsent('If-None-Match', () => hit.etag);
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    final etag = response.headers.value('etag');
    if (_enabled(options) &&
        options.extra[_generationKey] == _generation &&
        response.statusCode == 200 &&
        etag != null) {
      _store(_key(options), etag, response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 304 &&
        err.requestOptions.extra[_generationKey] == _generation) {
      final hit = _cache[_key(err.requestOptions)];
      if (hit != null) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: err.requestOptions,
            data: hit.data,
            statusCode: 200,
            statusMessage: 'OK (from ETag cache)',
            headers: hit.headers,
            extra: {'fromEtagCache': true},
          ),
        );
        return;
      }
    }
    handler.next(err);
  }

  void _store(String key, String etag, Response<dynamic> response) {
    _cache.remove(key);
    _cache[key] = _ETagEntry(
      etag: etag,
      data: response.data,
      headers: response.headers,
    );
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

class _ETagEntry {
  const _ETagEntry({
    required this.etag,
    required this.data,
    required this.headers,
  });
  final String etag;
  final dynamic data;
  final Headers headers;
}

/// **Debug-only** request tracer (added to the client only in debug builds, so
/// it's a no-op in release). Logs `method + full URL`, the response status with
/// round-trip time, and — on failure — the transport error type/message or the
/// API error code. A network failure therefore reveals *which host* it dialled
/// and *why* it failed (e.g. `connectionError — Failed host lookup`).
///
/// Bodies and headers are intentionally **not** logged: request bodies carry
/// passwords + Art. 9 content, and `Authorization` carries tokens.
class NetworkLogInterceptor extends Interceptor {
  const NetworkLogInterceptor();

  static const _startKey = 'x-log-start-ms';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    AppLogger.debug('→ ${options.method} ${options.uri}', tag: 'HTTP');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final r = response.requestOptions;
    AppLogger.debug(
      '← ${response.statusCode} ${r.method} ${r.uri}${_elapsed(r)}',
      tag: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final r = err.requestOptions;
    final status = err.response?.statusCode;
    final detail = status != null
        ? 'HTTP $status${_apiCode(err.response?.data)}'
        : '${err.type.name} — ${err.message ?? err.error}';
    AppLogger.warn(
      '✗ ${r.method} ${r.uri} · $detail${_elapsed(r)}',
      tag: 'HTTP',
    );
    handler.next(err);
  }

  String _elapsed(RequestOptions o) {
    final start = o.extra[_startKey] as int?;
    if (start == null) return '';
    return ' (${DateTime.now().millisecondsSinceEpoch - start}ms)';
  }

  /// Pulls `error.code` out of the standard `{error:{code,message,...}}`
  /// envelope so a 4xx/5xx shows e.g. `HTTP 409 (email_already_exists)` without
  /// dumping the body.
  String _apiCode(Object? data) {
    if (data is Map && data['error'] is Map) {
      final code = (data['error'] as Map)['code'];
      if (code != null) return ' ($code)';
    }
    return '';
  }
}
