import 'package:esferaup/core/utils/content_author.dart';
import 'package:esferaup/features/up/domain/entities/deleted_up.dart';
import 'package:esferaup/features/up/domain/entities/up_detail.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';

/// Wire DTOs for the UP endpoints (POST /profiles/{id}/ups + /crisis).
class UpCreateResultDto {
  const UpCreateResultDto({
    required this.id,
    required this.puntsAwarded,
    required this.dailyCapReached,
  });

  factory UpCreateResultDto.fromJson(Map<String, dynamic> json) =>
      UpCreateResultDto(
        id: json['id'] as String,
        puntsAwarded: (json['punts_awarded'] as num?)?.toInt() ?? 0,
        dailyCapReached: json['daily_cap_reached'] as bool? ?? false,
      );

  final String id;
  final int puntsAwarded;
  final bool dailyCapReached;
}

UpDetail upDetailFromJson(Map<String, dynamic> json) => UpDetail(
  id: json['id'] as String,
  profileId: json['profile_id'] as String,
  category: json['category'] as String,
  occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
  mood: _moodFromWire(json['mood'] as String?),
  note: json['note'] as String?,
  tag: json['tag'] as String?,
  categoryEditable: json['category_editable'] as bool? ?? true,
  isPinned: json['is_pinned'] as bool? ?? false,
  isCrisi: json['is_crisi'] as bool? ?? false,
  crisi: switch (json['crisi']) {
    final Map<String, dynamic> crisi => UpCrisiDetail(
      triggerText: crisi['trigger_text'] as String?,
      resolutionText: crisi['resolution_text'] as String?,
      durationBucket: crisi['duration_bucket'] as String?,
      moodAfter: _moodFromWire(crisi['mood_after'] as String?),
      draft: crisi['draft'] as bool? ?? false,
    ),
    _ => null,
  },
  attachments: [
    for (final raw in (json['attachments'] as List<dynamic>? ?? const []))
      UpAttachment(
        index: ((raw as Map<String, dynamic>)['attachment_index'] as num)
            .toInt(),
        mime: raw['mime'] as String,
        sizeBytes: (raw['size_bytes'] as num).toInt(),
      ),
  ],
  attachmentsPending: json['attachments_pending'] as bool? ?? false,
  createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  author: ContentAuthor.fromJson(
    json['author'],
    formerAuthor: json['former_author'],
  ),
);

DeletedUp deletedUpFromJson(Map<String, dynamic> json) => DeletedUp(
  id: json['id'] as String,
  profileId: json['profile_id'] as String,
  category: json['category'] as String,
  occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
  deletedAt: DateTime.parse(json['deleted_at'] as String).toLocal(),
  daysLeft: (json['days_left'] as num).toInt(),
  mood: _moodFromWire(json['mood'] as String?),
  preview: json['preview'] as String?,
  isCrisi: json['is_crisi'] as bool? ?? false,
  hasAttachment: json['has_attachment'] as bool? ?? false,
  restoreBlock: UpRestoreBlock.fromWire(
    json['restore_blocked_reason'] as String?,
  ),
);

UpAttachmentDownloadGrant upAttachmentDownloadGrantFromJson(
  Map<String, dynamic> json,
) => UpAttachmentDownloadGrant(
  url: Uri.parse(json['download_url'] as String),
  mime: json['mime'] as String,
  sizeBytes: (json['size_bytes'] as num).toInt(),
  expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
);

UpMood? _moodFromWire(String? wire) => switch (wire) {
  'happy' => UpMood.good,
  'love' => UpMood.great,
  'sad' => UpMood.sad,
  'angry' => UpMood.angry,
  'spark' => UpMood.excited,
  _ => null,
};
