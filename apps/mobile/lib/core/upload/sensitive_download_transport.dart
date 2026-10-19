import 'dart:io';

import 'package:dio/dio.dart';
import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';

const maxPlaceMaterialDownloadBytes = 50 * 1024 * 1024;

class SensitiveDownloadTooLarge implements Exception {
  const SensitiveDownloadTooLarge();
}

/// Streams a presigned object into the session-fenced sensitive cache.
/// The direct client has no app auth interceptors, so bearer credentials can
/// never leak to object storage.
class SensitiveDownloadTransport {
  SensitiveDownloadTransport(this._tempFiles, {Dio? directClient})
    : _direct =
          directClient ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final SensitiveTempFileStore _tempFiles;
  final Dio _direct;

  Future<File> downloadToTemp(
    Uri uri, {
    required String extension,
    required int maxBytes,
  }) async {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        maxBytes <= 0 ||
        maxBytes > maxPlaceMaterialDownloadBytes) {
      throw const FormatException('Unsafe sensitive download request.');
    }
    final destination = await _tempFiles.allocate(extension: extension);
    IOSink? sink;
    try {
      final response = await _direct.getUri<ResponseBody>(
        uri,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final declared = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declared != null && declared > maxBytes) {
        throw const SensitiveDownloadTooLarge();
      }
      final body = response.data;
      if (body == null) throw const FormatException('Download body missing.');
      sink = destination.openWrite();
      var received = 0;
      await for (final chunk in body.stream) {
        received += chunk.length;
        if (received > maxBytes) throw const SensitiveDownloadTooLarge();
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (declared != null && declared != received) {
        throw const FormatException('Download was interrupted.');
      }
      return destination;
    } on Object {
      await sink?.close();
      await _tempFiles.delete(destination);
      rethrow;
    }
  }

  Future<void> delete(File file) => _tempFiles.delete(file);
}
