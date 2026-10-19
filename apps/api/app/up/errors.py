"""UP + Crisi domain errors (Plan 019).

All subclass AppError → canonical envelope. Services raise these; routers translate.

Crisi error codes are deliberately NEUTRAL / non-alarming (the Crisi form is
"calm, supportive"): TRIGGER_REQUIRED, not "CRISIS_TRIGGER_MISSING". The mobile
layer (Plan 042) maps these to supportive 'moment difícil' copy.
"""

from __future__ import annotations

from app.errors import AppError


class UPNotFoundError(AppError):
    """UP absent / not visible / wrong tenant → 404 (default-deny, no oracle)."""

    def __init__(self) -> None:
        super().__init__(code="UP_NOT_FOUND", status_code=404, message="UP not found.")


class UPRestoreWindowExpiredError(AppError):
    """Restore asked for after the recovery window closed → 410."""

    def __init__(self) -> None:
        super().__init__(
            code="UP_RESTORE_WINDOW_EXPIRED",
            status_code=410,
            message="This UP can no longer be recovered.",
        )


# Why a deleted UP cannot be restored right now, by the code of the refusal the
# restore itself answers with. The "recently deleted" list carries the reason.
RESTORE_BLOCK_REASONS: dict[str, str] = {
    "CONSENT_NOT_FOUND": "consent_revoked",
    "PROFILE_MIGRATION_IN_PROGRESS": "profile_migrating",
    "PROFILE_AWAITING_ADULT_CONSENT": "awaiting_adult_consent",
    "PROFILE_ERASURE_REQUESTED": "erasure_requested",
}


class TriggerRequiredError(AppError):
    """A Crisi sidecar needs at least a trigger description → 422 (neutral copy)."""

    def __init__(self) -> None:
        super().__init__(
            code="TRIGGER_REQUIRED",
            status_code=422,
            message="A short description of what happened is required.",
            field="crisi.trigger_text",
        )


class IsCrisiImmutableError(AppError):
    """PATCH tried to flip is_crisi → 422 (round-2 CRITICAL).

    The sidecar TX boundary cannot be re-established post-hoc; flipping would either
    trip the deferred trigger (true) or orphan the sidecar (false). Soft-delete the
    UP and create a new one instead.
    """

    def __init__(self) -> None:
        super().__init__(
            code="IS_CRISI_IMMUTABLE_AFTER_CREATE",
            status_code=422,
            message=(
                "Whether an entry is a difficult moment cannot be changed after it is "
                "created. Delete it and create a new one instead."
            ),
            field="is_crisi",
        )


class CrisiMomentFixedError(AppError):
    """The moment of a completed crisis cannot be moved → 422."""

    def __init__(self) -> None:
        super().__init__(
            code="CRISI_MOMENT_FIXED",
            status_code=422,
            message="Only an unfinished crisis can change its moment.",
            field="crisi.occurred_at",
        )


class NotACrisiError(AppError):
    """redact / reclassify called on a UP that has no Crisi sidecar → 404."""

    def __init__(self) -> None:
        super().__init__(
            code="NOT_A_CRISI",
            status_code=404,
            message="This entry has no difficult-moment details to redact.",
        )


class AttachmentLimitExceededError(AppError):
    """> 5 attachments on a single UP (Q106 / API.md §8.6) → 422."""

    def __init__(self, limit: int) -> None:
        super().__init__(
            code="ATTACHMENT_LIMIT_EXCEEDED",
            status_code=422,
            message=f"A UP may have at most {limit} attachments.",
            field="attachments",
        )


class AudioAttachmentLimitExceededError(AppError):
    """The UP exceeds the subscription tier's audio-note allowance."""

    def __init__(self, limit: int) -> None:
        attachment_label = "attachment" if limit == 1 else "attachments"
        super().__init__(
            code="AUDIO_ATTACHMENT_LIMIT_EXCEEDED",
            status_code=422,
            message=(f"This subscription allows at most {limit} audio {attachment_label} per UP."),
            field="attachments",
            details=[{"audio_limit": limit}],
        )


class AttachmentRejectedError(AppError):
    """Upload is absent, unsafe, mismatched, unverified, or already owned."""

    def __init__(self) -> None:
        super().__init__(
            code="ATTACHMENT_REJECTED",
            status_code=422,
            message="The attachment could not be added to this UP.",
            field="attachments",
        )


class AttachmentIndexError(AppError):
    """attach-arxiu referenced a UP attachment index that does not exist → 422.

    Lives in the UP domain (the UP owns the attachment) so UpBackLinkPort's UP-side
    validation does not import app.document (keeps both walls clean).
    """

    def __init__(self) -> None:
        super().__init__(
            code="ATTACHMENT_INDEX_OUT_OF_RANGE",
            status_code=422,
            message="The UP has no attachment at that index.",
            field="attachment_index",
        )
