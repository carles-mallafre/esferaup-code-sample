import 'package:esferaup/core/network/dio_client.dart';
import 'package:esferaup/core/upload/sensitive_download_transport.dart';
import 'package:esferaup/core/upload/sensitive_temp_file_store.dart';
import 'package:esferaup/core/upload/upload_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'upload_providers.g.dart';

@Riverpod(keepAlive: true)
SensitiveTempFileStore sensitiveTempFileStore(Ref ref) =>
    SensitiveTempFileStore();

@Riverpod(keepAlive: true)
SensitiveDownloadTransport sensitiveDownloadTransport(Ref ref) =>
    SensitiveDownloadTransport(ref.watch(sensitiveTempFileStoreProvider));

Future<void> prepareSensitiveTempStoreForAuthenticatedStartup(
  SensitiveTempFileStore store,
) async {
  await store.cleanupAll();
  store.beginSession();
}

@Riverpod(keepAlive: true)
UploadTransport uploadTransport(Ref ref) =>
    UploadTransport(ref.watch(dioProvider));
