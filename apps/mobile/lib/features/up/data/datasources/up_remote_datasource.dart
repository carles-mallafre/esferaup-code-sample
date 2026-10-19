import 'package:dio/dio.dart';
import 'package:esferaup/features/up/data/models/up_dtos.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:uuid/uuid.dart';

/// Raw HTTP for the UP capture endpoints. Uses the app's main [Dio] (auth +
/// retry interceptors attached). POSTs carry a fresh `Idempotency-Key`
/// (API.md §11) so a double-tap replays the same UP instead of duplicating it.
class UpRemoteDataSource {
  UpRemoteDataSource(this._dio);

  final Dio _dio;
  static const _uuid = Uuid();

  Future<UpDetail> getUp(String upId) async {
    final res = await _dio.get<Map<String, dynamic>>('/ups/$upId');
    return upDetailFromJson(res.data!);
  }

  Future<UpAttachmentDownloadGrant> getAttachmentDownloadGrant({
    required String upId,
    required int attachmentIndex,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/ups/$upId/attachments/$attachmentIndex/download',
      options: Options(extra: const {'etagCache': false}),
    );
    return upAttachmentDownloadGrantFromJson(res.data!);
  }

  Future<bool> setPinned({required String upId, required bool pinned}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/ups/$upId/${pinned ? 'pin-memory' : 'unpin-memory'}',
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
    return res.data!['is_pinned'] as bool;
  }

  Future<void> deleteUp(String upId) async {
    await _dio.delete<void>(
      '/ups/$upId',
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
  }

  Future<List<DeletedUp>> listDeletedUps(String profileId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/ups/deleted',
      queryParameters: {'profile_id': profileId},
      options: Options(extra: const {'etagCache': false}),
    );
    return [
      for (final raw in (res.data!['items'] as List<dynamic>? ?? const []))
        deletedUpFromJson(raw as Map<String, dynamic>),
    ];
  }

  Future<void> restoreUp(String upId) async {
    await _dio.post<Map<String, dynamic>>(
      '/ups/$upId/restore',
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
  }

  Future<UpDetail> patchUp({
    required String upId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/ups/$upId',
      data: body,
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
    return upDetailFromJson(res.data!);
  }

  Future<UpCreateResultDto> createUp({
    required String profileId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/profiles/$profileId/ups',
      data: body,
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
    return UpCreateResultDto.fromJson(res.data!);
  }

  Future<UpCreateResultDto> createCrisi({
    required String profileId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/profiles/$profileId/crisis',
      data: body,
      options: Options(headers: {'Idempotency-Key': _uuid.v4()}),
    );
    return UpCreateResultDto.fromJson(res.data!);
  }
}
