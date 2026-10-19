import 'package:esferaup/features/up/domain/up_mood.dart';

/// How long a deleted UP can be restored; the server enforces the same window.
const upRecoveryDays = 7;

/// Why a deleted UP cannot be restored right now. The server re-checks the
/// profile's consent and write state at restore time, not at delete time.
enum UpRestoreBlock {
  consentRevoked('consent_revoked', 'CONSENT_NOT_FOUND'),
  profileMigrating('profile_migrating', 'PROFILE_MIGRATION_IN_PROGRESS'),
  awaitingAdultConsent(
    'awaiting_adult_consent',
    'PROFILE_AWAITING_ADULT_CONSENT',
  ),
  erasureRequested('erasure_requested', 'PROFILE_ERASURE_REQUESTED');

  const UpRestoreBlock(this.wire, this.errorCode);

  /// `restore_blocked_reason` on the "recently deleted" list.
  final String wire;

  /// The error code a refused restore answers with.
  final String errorCode;

  static UpRestoreBlock? fromWire(String? value) {
    for (final block in values) {
      if (block.wire == value) return block;
    }
    return null;
  }

  static UpRestoreBlock? fromErrorCode(String? code) {
    for (final block in values) {
      if (block.errorCode == code) return block;
    }
    return null;
  }
}

/// A UP a family member deleted that can still be restored.
class DeletedUp {
  const DeletedUp({
    required this.id,
    required this.profileId,
    required this.category,
    required this.occurredAt,
    required this.deletedAt,
    required this.daysLeft,
    this.mood,
    this.preview,
    this.isCrisi = false,
    this.hasAttachment = false,
    this.restoreBlock,
  });

  final String id;
  final String profileId;
  final String category;
  final DateTime occurredAt;
  final DateTime deletedAt;

  /// Whole days left to restore, rounded up (never below 1).
  final int daysLeft;
  final UpMood? mood;
  final String? preview;
  final bool isCrisi;
  final bool hasAttachment;

  /// Set when a restore would be refused now; the row says why instead of
  /// offering the action.
  final UpRestoreBlock? restoreBlock;
}
