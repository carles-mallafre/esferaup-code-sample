/// Sealed error hierarchy for the whole app. Carries the backend envelope's
/// `code` + `field` + `request_id` ONLY — the presentation layer maps
/// `code → localized ARB string`, so messages honor ca/es/en and no raw server
/// copy is shown to users (divergence from elmetodo's hardcoded Spanish).
///
/// Backend envelope: `{ "error": { "code", "message", "request_id", "field?",
/// "details?" } }`.
sealed class AppError implements Exception {
  const AppError({this.code, this.requestId, this.debugMessage});

  /// Stable machine code from the envelope (e.g. `TOKEN_INVALIDATED`,
  /// `PASSWORD_TOO_WEAK`). Used by the UI to pick a localized message.
  final String? code;

  /// Correlates with the backend log line / Sentry event.
  final String? requestId;

  /// Server `message` — for logs/Crashlytics only, never shown raw to users.
  final String? debugMessage;

  @override
  String toString() =>
      '$runtimeType(code: $code, requestId: $requestId, debug: $debugMessage)';
}

/// Timeout / no-connection. NEVER triggers logout.
class NetworkError extends AppError {
  const NetworkError({super.debugMessage}) : super(code: 'NETWORK');
}

/// 5xx — server fault. Carries request_id for support.
class ServerError extends AppError {
  const ServerError({super.code, super.requestId, super.debugMessage});
}

/// 401/403 — unauthenticated/forbidden. [hardLogout] true for
/// `TOKEN_INVALIDATED` / role-change (migració-at-18) / admin revoke.
class AuthError extends AppError {
  const AuthError({
    super.code,
    super.requestId,
    super.debugMessage,
    this.hardLogout = false,
    this.items = const [],
  });

  final bool hardLogout;

  /// The envelope's `details` when the server sends a list of objects (e.g.
  /// the family and profile a `LAST_ADMIN_CANNOT_LEAVE` refers to).
  final List<Map<String, Object?>> items;
}

/// 422 — validation. [field] binds to a specific form field's error.
class ValidationError extends AppError {
  const ValidationError({
    super.code,
    super.requestId,
    super.debugMessage,
    this.field,
    this.details,
  });

  final String? field;
  final Map<String, Object?>? details;
}

/// 409 — a state/version conflict that the user can usually resolve and retry.
class ConflictError extends AppError {
  const ConflictError({super.code, super.requestId, super.debugMessage});
}

/// OS permission denied (camera/mic/notifications/photos).
class PermissionError extends AppError {
  const PermissionError({super.code, super.debugMessage, this.permission});

  final String? permission;
}

/// 429 — rate limited. [retryAfter] from the `Retry-After` header; D14/no-auth
/// surfaces an upsell.
class RateLimitError extends AppError {
  const RateLimitError({
    super.code,
    super.requestId,
    super.debugMessage,
    this.retryAfter,
  });

  final Duration? retryAfter;
}

/// Upload blocked by the Plan 028 moderation pipeline ("report/takedown" copy).
class ModerationError extends AppError {
  const ModerationError({super.code, super.requestId, super.debugMessage});
}

/// 423 — the profile refuses writes: a handoff is in progress, the new adult
/// has not answered after turning 18, or they asked for their data to be
/// erased. [reason] tells which; reading keeps working in all three.
class MigrationLockedError extends AppError {
  const MigrationLockedError({super.code, super.requestId, super.debugMessage});

  ProfileWriteBlock get reason => profileWriteBlockForCode(code);
}

enum ProfileWriteBlock {
  handoffInProgress,
  awaitingAdultConsent,
  erasureRequested,
}

ProfileWriteBlock profileWriteBlockForCode(String? code) => switch (code) {
  'PROFILE_AWAITING_ADULT_CONSENT' => ProfileWriteBlock.awaitingAdultConsent,
  'PROFILE_ERASURE_REQUESTED' => ProfileWriteBlock.erasureRequested,
  _ => ProfileWriteBlock.handoffInProgress,
};

/// Anything unmapped.
class UnknownError extends AppError {
  const UnknownError({super.code, super.requestId, super.debugMessage});
}
