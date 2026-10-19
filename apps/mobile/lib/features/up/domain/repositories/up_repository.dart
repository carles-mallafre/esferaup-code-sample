import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_save_result.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';

/// Port for the UP capture flow (Plan 019 client — 091-WP06).
abstract interface class UpRepository {
  Future<UpDetail> getUp(String upId);

  Future<UpAttachmentDownloadGrant> getAttachmentDownloadGrant({
    required String upId,
    required int attachmentIndex,
  });

  Future<bool> setPinned({required String upId, required bool pinned});

  Future<void> deleteUp(String upId);

  /// The profile's UPs deleted inside the recovery window, newest first.
  Future<List<DeletedUp>> listDeletedUps(String profileId);

  Future<void> restoreUp(String upId);

  Future<UpSaveResult> createUp({
    required String profileId,
    required String category,
    required DateTime occurredAt,
    UpMood? mood,
    String? note,
    String? tag,
    List<String> attachmentUploadKeys = const [],
    bool saveToArxiu = false,
  });

  Future<UpDetail> updateUp({
    required String upId,
    required String category,
    required UpMood? mood,
    required String note,
    required String? tag,
  });

  Future<UpSaveResult> createCrisi({
    required String profileId,
    required DateTime occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    bool draft = false,
  });

  /// Completes (or re-saves) an "Acabar més tard" Crisi draft in place,
  /// including the moment when it was changed on the form.
  Future<UpDetail> updateCrisi({
    required String upId,
    DateTime? occurredAt,
    String? triggerText,
    String? resolutionText,
    String? durationBucket,
    UpMood? moodAfter,
    required bool draft,
  });
}
