import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:esferaup/core/config/env.dart';

/// Per-request override of [Env.requestDeadline], as a [Duration] in
/// `Options.extra`. Only for calls known to take longer than the default.
const requestDeadlineExtra = 'requestDeadline';

const _deadlineAtKey = 'x-deadline-at-us';
const _budgetKey = 'x-deadline-budget-us';

/// Stamps one deadline per logical request. Retries reuse the same
/// [RequestOptions], so the first stamp also bounds every replay.
class RequestDeadlineInterceptor extends Interceptor {
  RequestDeadlineInterceptor({this.budget = Env.requestDeadline});

  final Duration budget;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.extra.containsKey(_deadlineAtKey)) {
      final override = options.extra[requestDeadlineExtra];
      final effective = override is Duration ? override : budget;
      options.extra[_budgetKey] = effective.inMicroseconds;
      options.extra[_deadlineAtKey] = DateTime.now()
          .add(effective)
          .microsecondsSinceEpoch;
    }
    handler.next(options);
  }
}

/// What is left of the request's deadline, or null when none was stamped.
Duration? requestTimeLeft(RequestOptions options) {
  final at = options.extra[_deadlineAtKey];
  if (at is! int) return null;
  return Duration(microseconds: at - DateTime.now().microsecondsSinceEpoch);
}

/// Bounds connect + send + wait-for-response of one attempt by the time left on
/// the request's deadline. Dio's own timeouts are per phase: `sendTimeout` is
/// unset, so a body the server never reads hangs, and connect + receive add up.
class DeadlineHttpClientAdapter implements HttpClientAdapter {
  DeadlineHttpClientAdapter(this._inner);

  final HttpClientAdapter _inner;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final left = requestTimeLeft(options);
    if (left == null) return _inner.fetch(options, requestStream, cancelFuture);
    if (left <= Duration.zero) return Future.error(_expired(options));

    final abort = Completer<void>();
    final expired = Completer<ResponseBody>();
    cancelFuture?.then(
      (_) => abort.isCompleted ? null : abort.complete(),
      onError: (Object _) => abort.isCompleted ? null : abort.complete(),
    );
    final timer = Timer(left, () {
      if (!abort.isCompleted) abort.complete();
      expired.completeError(_expired(options));
    });
    final attempt = _inner.fetch(options, requestStream, abort.future);
    return Future.any([attempt, expired.future]).whenComplete(timer.cancel);
  }

  DioException _expired(RequestOptions options) {
    final budget = options.extra[_budgetKey];
    return DioException.receiveTimeout(
      timeout: budget is int
          ? Duration(microseconds: budget)
          : Env.requestDeadline,
      requestOptions: options,
    );
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
