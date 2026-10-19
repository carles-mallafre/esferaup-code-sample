import 'package:esferaup/core/utils/content_author.dart';
import 'package:esferaup/features/up/domain/up_mood.dart';

class UpAttachment {
  const UpAttachment({
    required this.index,
    required this.mime,
    required this.sizeBytes,
  });

  final int index;
  final String mime;
  final int sizeBytes;

  bool get isImage =>
      mime == 'image/jpeg' ||
      mime == 'image/png' ||
      mime == 'image/webp' ||
      mime == 'image/heic';

  bool get isAudio => mime == 'audio/mp4';
}

/// Decrypted Crisi sidecar. `draft` marks an "Acabar més tard" entry that
/// still has to be completed from the Crisi form.
class UpCrisiDetail {
  const UpCrisiDetail({
    this.triggerText,
    this.resolutionText,
    this.durationBucket,
    this.moodAfter,
    this.draft = false,
  });

  final String? triggerText;
  final String? resolutionText;
  final String? durationBucket;
  final UpMood? moodAfter;
  final bool draft;
}

class UpDetail {
  const UpDetail({
    required this.id,
    required this.profileId,
    required this.category,
    required this.occurredAt,
    required this.isPinned,
    required this.isCrisi,
    required this.createdAt,
    this.mood,
    this.note,
    this.tag,
    this.categoryEditable = true,
    this.crisi,
    this.attachments = const [],
    this.attachmentsPending = false,
    this.author,
  });

  final String id;
  final String profileId;
  final String category;
  final DateTime occurredAt;
  final UpMood? mood;
  final String? note;
  final String? tag;
  final bool categoryEditable;
  final bool isPinned;
  final bool isCrisi;
  final UpCrisiDetail? crisi;
  final List<UpAttachment> attachments;
  final bool attachmentsPending;
  final DateTime createdAt;

  /// Set when the adult who wrote it has erased their account.
  final ContentAuthor? author;

  bool get isCrisiDraft => crisi?.draft ?? false;

  UpDetail copyWith({bool? isPinned}) => UpDetail(
    id: id,
    profileId: profileId,
    category: category,
    occurredAt: occurredAt,
    mood: mood,
    note: note,
    tag: tag,
    categoryEditable: categoryEditable,
    isPinned: isPinned ?? this.isPinned,
    isCrisi: isCrisi,
    crisi: crisi,
    attachments: attachments,
    attachmentsPending: attachmentsPending,
    createdAt: createdAt,
    author: author,
  );
}

class UpAttachmentDownloadGrant {
  const UpAttachmentDownloadGrant({
    required this.url,
    required this.mime,
    required this.sizeBytes,
    required this.expiresAt,
  });

  final Uri url;
  final String mime;
  final int sizeBytes;
  final DateTime expiresAt;

  bool get isSafeHttp => url.scheme == 'https' || url.scheme == 'http';
}
