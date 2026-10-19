import 'package:dio/dio.dart';
import 'package:esferaup/core/errors/error_mapper.dart';
import 'package:esferaup/features/up/data/datasources/up_remote_datasource.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_save_result.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/repositories/up_repository.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';

/// Maps the UI's UpMood onto the wire Mood vocabulary (schemas/up.py).
const _moodWire = {
  UpMood.good: 'happy',
  UpMood.great: 'love',
  UpMood.sad: 'sad',
  UpMood.angry: 'angry',
  UpMood.excited: 'spark',
};

class UpRepositoryImpl implements UpRepository {
  UpRepositoryImpl(this._remote);

  final UpRemoteDataSource _remote;

  @override
  Future<UpDetail> getUp(String upId) => _guard(() => _remote.getUp(upId));

  @override
  Future<UpAttachmentDownloadGrant> getAttachmentDownloadGrant({
    required String upId,
    required int attachmentIndex,
  }) => _guard(
    () => _remote.getAttachmentDownloadGrant(
      upId: upId,
      attachmentIndex: attachmentIndex,
    ),
  );

  @override
  Future<bool> setPinned({required String upId, required bool pinned}) =>
      _guard(() => _remote.setPinned(upId: upId, pinned: pinned));

  @override
  Future<void> deleteUp(String upId) => _guard(() => _remote.deleteUp(upId));

  @override
  Future<List<DeletedUp>> listDeletedUps(String profileId) =>
      _guard(() => _remote.listDeletedUps(profileId));

  @override
  Future<void> restoreUp(String upId) => _guard(() => _remote.restoreUp(upId));

  @override
  Future<UpSaveResult> createUp({
    required String profileId,
    required String category,
    required DateTime occurredAt,
    UpMood? mood,
    String? note,
    String? tag,
    List<String> attachmentUploadKeys = const [],
    bool saveToArxiu = false,
  }) => _guard(() async {
    final dto = await _remote.createUp(
      profileId: profileId,
      body: {
        'category': category,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (mood != null) 'mood': _moodWire[mood],
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (tag != null && tag.trim().isNotEmpty) 'tag': tag.trim(),
        if (attachmentUploadKeys.isNotEmpty)
          'attachments': [
            for (final uploadKey in attachmentUploadKeys)
              {'upload_key': uploadKey},
          ],
        // The API files the attachment under Arxiu "altres"; the family can
        // move it to the right section from the archive itself.
        if (saveToArxiu) 'save_to_arxiu': true,
      },
    );
    return UpSaveResult(
      id: dto.id,
      puntsAwarded: dto.puntsAwarded,
      dailyCapReached: dto.dailyCapReached,
    );
  });

  @override
  Future<UpDetail> updateUp({
    required String upId,
    required String category,
    required UpMood? mood,
    required String note,
    required String? tag,
  }) => _guard(
    () => _remote.patchUp(
      upId: upId,
      body: {
        'category': category,
        if (mood != null) 'mood': _moodWire[mood],
        'note': note.trim(),
        'tag': tag?.trim().isEmpty == true ? null : tag?.trim(),
      },
    ),
  );

  @override
  Future<UpSaveResult> createCrisi({
    required String profileId,
    required DateTime occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    bool draft = false,
  }) => _guard(() async {
    final dto = await _remote.createCrisi(
      profileId: profileId,
      body: {
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        if (triggerText != null && triggerText.trim().isNotEmpty)
          'trigger_text': triggerText.trim(),
        if (resolutionText != null && resolutionText.trim().isNotEmpty)
          'resolution_text': resolutionText.trim(),
        if (durationBucket != null) 'duration_bucket': durationBucket,
        if (moodAfter != null) 'mood_after': _moodWire[moodAfter],
        if (draft) 'draft': true,
      },
    );
    return UpSaveResult(
      id: dto.id,
      puntsAwarded: dto.puntsAwarded,
      dailyCapReached: dto.dailyCapReached,
    );
  });

  @override
  Future<UpDetail> updateCrisi({
    required String upId,
    DateTime? occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    required bool draft,
  }) => _guard(
    () => _remote.patchUp(
      upId: upId,
      body: {
        'crisi': {
          if (occurredAt != null)
            'occurred_at': occurredAt.toUtc().toIso8601String(),
          if (triggerText != null && triggerText.trim().isNotEmpty)
            'trigger_text': triggerText.trim(),
          if (resolutionText != null && resolutionText.trim().isNotEmpty)
            'resolution_text': resolutionText.trim(),
          if (durationBucket != null) 'duration_bucket': durationBucket,
          if (moodAfter != null) 'mood_after': _moodWire[moodAfter],
          'draft': draft,
        },
      },
    ),
  );

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw dioErrorToAppError(e);
    }
  }
}
