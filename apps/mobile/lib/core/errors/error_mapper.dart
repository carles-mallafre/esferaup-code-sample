import 'package:dio/dio.dart';
import 'package:esferaup/core/errors/app_error.dart';

/// Maps a [DioException] (and its `{error:{...}}` envelope) into a typed
/// [AppError]. Single place that knows the wire→error contract.
AppError dioErrorToAppError(DioException e) {
  // Transport failures — no HTTP response. Never a logout.
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return NetworkError(debugMessage: e.message);
    case DioExceptionType.cancel:
      return const NetworkError(debugMessage: 'cancelled');
    case DioExceptionType.badCertificate:
      return const NetworkError(debugMessage: 'bad certificate');
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }

  final response = e.response;
  final status = response?.statusCode;
  final env = _Envelope.parse(response?.data);

  if (status == null) return NetworkError(debugMessage: e.message);

  switch (status) {
    case 401:
    case 403:
      const hardCodes = {
        'TOKEN_INVALIDATED',
        'ROLE_CHANGED',
        'SESSION_REVOKED',
      };
      return AuthError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
        hardLogout: status == 401 && hardCodes.contains(env.code),
        items: env.items,
      );
    case 422:
      return ValidationError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
        field: env.field,
        details: env.details,
      );
    case 409:
      return ConflictError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
      );
    case 423:
      return MigrationLockedError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
      );
    case 429:
      return RateLimitError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
        retryAfter: _retryAfter(response),
      );
    default:
      if (env.code == 'CONTENT_BLOCKED' || env.code == 'MODERATION_BLOCKED') {
        return ModerationError(
          code: env.code,
          requestId: env.requestId,
          debugMessage: env.message,
        );
      }
      if (status >= 500) {
        return ServerError(
          code: env.code,
          requestId: env.requestId,
          debugMessage: env.message,
        );
      }
      return UnknownError(
        code: env.code,
        requestId: env.requestId,
        debugMessage: env.message,
      );
  }
}

Duration? _retryAfter(Response<dynamic>? response) {
  final raw = response?.headers.value('retry-after');
  final secs = int.tryParse(raw ?? '');
  return secs == null ? null : Duration(seconds: secs);
}

/// Tolerant view over the `{error:{code,message,request_id,field,details}}` body.
class _Envelope {
  const _Envelope({
    this.code,
    this.message,
    this.requestId,
    this.field,
    this.details,
    this.items = const [],
  });

  final String? code;
  final String? message;
  final String? requestId;
  final String? field;
  final Map<String, Object?>? details;
  final List<Map<String, Object?>> items;

  static _Envelope parse(Object? data) {
    if (data is! Map) return const _Envelope();
    final error = data['error'];
    if (error is! Map) return const _Envelope();
    return _Envelope(
      code: error['code'] as String?,
      message: error['message'] as String?,
      requestId: error['request_id'] as String?,
      field: error['field'] as String?,
      details: error['details'] is Map
          ? (error['details'] as Map).cast<String, Object?>()
          : null,
      items: error['details'] is List
          ? [
              for (final item in error['details'] as List)
                if (item is Map) item.cast<String, Object?>(),
            ]
          : const [],
    );
  }
}
