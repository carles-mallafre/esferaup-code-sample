import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:esferaup/core/config/env.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Result of the authenticated presign step in the shared upload pipeline.
class PresignedUpload {
  const PresignedUpload({
    required this.uploadKey,
    required this.uploadUrl,
    required this.expiresAt,
  });

  final String uploadKey;
  final Uri uploadUrl;
  final DateTime expiresAt;
}

/// Typed status returned by the Plan 028 quarantine pipeline.
enum UploadPipelineStatus {
  pending,
  ready,
  rejected,
  quarantined,
  pendingAdminReview,
  unknown;

  static UploadPipelineStatus fromWire(String value) => switch (value) {
    'pending' => pending,
    'ready' => ready,
    'rejected' => rejected,
    'quarantined' => quarantined,
    'pending_admin_review' => pendingAdminReview,
    _ => unknown,
  };
}

/// Shared presign → direct PUT → verify transport used by every mobile upload.
///
/// The direct PUT uses a bare [Dio] with no application interceptors. Auth or
/// JSON headers added to a presigned URL would invalidate its signature. Domain
/// repositories remain responsible for attaching the returned key to their own
/// authoritative create/mutation request.
///
/// A storage connection that stops answering must not hang the upload: the PUT
/// has a connect timeout, a send budget that grows with the body (at least
/// [_minSendBytesPerSecond]) and a bounded wait for the storage's answer.
class UploadTransport {
  UploadTransport(
    this._api, {
    Dio Function()? directClientFactory,
    this.directResponseTimeout = Env.receiveTimeout,
  }) : _directClientFactory =
           directClientFactory ??
           (() => Dio(BaseOptions(connectTimeout: Env.connectTimeout)));

  static const _minSendBytesPerSecond = 32 * 1024;

  final Dio _api;
  final Dio Function() _directClientFactory;
  final Duration directResponseTimeout;

  Future<PresignedUpload> presign({
    required String context,
    required String profileId,
    required String mime,
    required int sizeBytes,
    required String sha256Hex,
    CancelToken? cancelToken,
  }) async {
    final operationId = _uuid.v4();
    final response = await _api.post<Map<String, dynamic>>(
      '/uploads/presign',
      data: {
        'context': context,
        'profile_id': profileId,
        'mime': mime,
        'size_bytes': sizeBytes,
        'sha256_content_address': sha256Hex,
      },
      options: Options(extra: {'idempotencyKey': operationId}),
      cancelToken: cancelToken,
    );
    final data = response.data!;
    final url = Uri.parse(data['upload_url'] as String);
    final localHttp =
        url.scheme == 'http' &&
        (url.host == 'localhost' ||
            url.host == '127.0.0.1' ||
            url.host == '::1');
    if ((url.scheme != 'https' && !localHttp) || url.host.isEmpty) {
      throw const FormatException('Presigned upload URL is not a safe target.');
    }
    return PresignedUpload(
      uploadKey: data['upload_key'] as String,
      uploadUrl: url,
      expiresAt: DateTime.parse(data['expires_at'] as String).toUtc(),
    );
  }

  Future<PresignedUpload> uploadBytes({
    required String context,
    required String profileId,
    required Uint8List bytes,
    required String mime,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final presigned = await presign(
      context: context,
      profileId: profileId,
      mime: mime,
      sizeBytes: bytes.length,
      sha256Hex: sha256.convert(bytes).toString(),
      cancelToken: cancelToken,
    );
    await _put(
      presigned,
      mime: mime,
      sizeBytes: bytes.length,
      bodyFactory: () => Stream<List<int>>.value(bytes),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
    await verify(presigned.uploadKey, cancelToken: cancelToken);
    return presigned;
  }

  /// Uploads a copied, app-owned file without loading a 50 MB PDF into memory.
  Future<PresignedUpload> uploadFile({
    required String context,
    required String profileId,
    required File file,
    required String mime,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final sizeBytes = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final presigned = await presign(
      context: context,
      profileId: profileId,
      mime: mime,
      sizeBytes: sizeBytes,
      sha256Hex: digest.toString(),
      cancelToken: cancelToken,
    );
    await _put(
      presigned,
      mime: mime,
      sizeBytes: sizeBytes,
      bodyFactory: file.openRead,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
    await verify(presigned.uploadKey, cancelToken: cancelToken);
    return presigned;
  }

  Future<void> _put(
    PresignedUpload presigned, {
    required String mime,
    required int sizeBytes,
    required Stream<List<int>> Function() bodyFactory,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: presigned.uploadUrl.toString()),
          reason: cancelToken?.cancelError?.error,
        );
      }
      try {
        final direct = _directClientFactory();
        await direct.putUri<void>(
          presigned.uploadUrl,
          data: bodyFactory(),
          options: Options(
            headers: {'Content-Type': mime, 'Content-Length': sizeBytes},
            contentType: mime,
            sendTimeout:
                Env.requestDeadline +
                Duration(seconds: sizeBytes ~/ _minSendBytesPerSecond),
            receiveTimeout: directResponseTimeout,
          ),
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
        );
        return;
      } on DioException catch (error) {
        lastError = error;
        if (!_retryablePut(error) ||
            attempt == 1 ||
            DateTime.now().toUtc().isAfter(presigned.expiresAt)) {
          rethrow;
        }
      }
    }
    throw lastError!;
  }

  bool _retryablePut(DioException error) => switch (error.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => true,
    DioExceptionType.badResponse =>
      (error.response?.statusCode ?? 0) >= 500 &&
          (error.response?.statusCode ?? 0) <= 504,
    DioExceptionType.badCertificate ||
    DioExceptionType.cancel ||
    DioExceptionType.unknown => false,
  };

  Future<void> verify(String uploadKey, {CancelToken? cancelToken}) async {
    await _api.post<void>(
      '/uploads/verify',
      data: {'upload_key': uploadKey},
      options: Options(extra: {'idempotencyKey': _uuid.v4()}),
      cancelToken: cancelToken,
    );
  }

  Future<UploadPipelineStatus> status(
    String uploadKey, {
    CancelToken? cancelToken,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/uploads/status',
      queryParameters: {'upload_key': uploadKey},
      options: Options(extra: {'etagCache': false}),
      cancelToken: cancelToken,
    );
    return UploadPipelineStatus.fromWire(response.data!['status'] as String);
  }
}
