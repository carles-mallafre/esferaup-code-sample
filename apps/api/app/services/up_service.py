"""UPService — the most load-bearing transaction in the API (Plan 019).

PREPARE-then-PERSIST (round-2 HIGH robustness):
  1. PREPARE: do ALL encryption + tokenisation first, with ZERO DB writes. If any
     encrypt raises (KmsUnavailableError → 503), no rows are written. This is the
     never-plaintext-Art9 invariant: an Art-9 write when KMS is down returns 503,
     it NEVER falls back to plaintext.
  2. PERSIST: a single TX (no commit — the router commits) writes UP → sidecar →
     FeedEntry → EsferaRadius → points → outbox → audit. Partial completion is the
     elmetodo SubscriptionStateService anti-pattern and is structurally precluded.

Option-H note routing (Q36): ART9_CATEGORIES = {salut, emocions} use note_encrypted
+ note_search_tokens (note_plain=None); everything else uses note_plain (encrypted
column NULL, tokens empty). Crisi (trigger/resolution) is ALWAYS Art-9.

save_to_arxiu (round-2 CRITICAL): we DO NOT import app.document. We write an outbox
sub-event `up.saved_to_arxiu_requested`; Plan 023 drains it into a Document. This
keeps the UP domain isolated (import-linter clean) while the user still sees the
document appear shortly after.

Lint A3: services raise AppError subclasses, never HTTPException. KmsUnavailableError
propagates to the global 503 handler.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import cast

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.event_kinds import AuditEventKind
from app.audit.repository import AuditEventRepository
from app.audit.schemas import NewAuditEvent
from app.billing.entitlement import SubscriptionEntitlementReader
from app.encryption import decrypt_field_for_tenant, encrypt_field_for_tenant, search_tokens
from app.errors import AppError
from app.family.content_author import load_family_authors
from app.family.profile_write_lock import lock_profile_for_write, read_profile_write_block
from app.gdpr.consent import ConsentRepository, ConsentService, requires_profile_consent
from app.gdpr.special_category_log import (
    SpecialCategoryAccessLogRepository,
    SpecialCategoryAccessLogService,
)
from app.repositories.esfera_repository import EsferaRadiusRepository
from app.repositories.feed_repository import FeedRepository
from app.repositories.up_repository import (
    UP_RECOVERY_WINDOW,
    OutboxRepository,
    UPCrisiRepository,
    UPRepository,
)
from app.repositories.upload_repository import UploadRepository
from app.schemas.common import former_author
from app.schemas.up import (
    MAX_ATTACHMENTS,
    CrisiData,
    CrisiPatchData,
    DurationBucket,
    Mood,
    UPCreateRequest,
    UPPatchRequest,
)
from app.services.points_service import PointsService
from app.shared.ports import AttachmentOwnershipRejectedError
from app.up.errors import (
    RESTORE_BLOCK_REASONS,
    AttachmentLimitExceededError,
    AttachmentRejectedError,
    AudioAttachmentLimitExceededError,
    CrisiMomentFixedError,
    IsCrisiImmutableError,
    NotACrisiError,
    TriggerRequiredError,
    UPNotFoundError,
    UPRestoreWindowExpiredError,
)
from app.up.permissions import assert_profile_role, assert_up_role
from app.uploads.constants import (
    CONTEXT_ACTIVA_PROOF,
    CONTEXT_UP_AUDIO,
    CONTEXT_UP_DOCUMENT,
    CONTEXT_UP_IMAGE,
)

logger = structlog.get_logger(__name__)

ART9_CATEGORIES: frozenset[str] = frozenset({"salut", "emocions"})
_PREVIEW_LEN = 140


def _is_art9(category: str, *, is_crisi: bool) -> bool:
    """A UP is Art-9 if its category is salut/emocions OR it is a Crisi."""
    return category in ART9_CATEGORIES or is_crisi


@dataclass
class _NotePrepared:
    """Encryption result for the note column (Option-H)."""

    plain: str | None = None
    encrypted: bytes | None = None
    tokens: list[int] = field(default_factory=list)


@dataclass
class _CrisiPrepared:
    trigger_encrypted: bytes | None
    resolution_encrypted: bytes | None
    tokens: list[int]
    duration_bucket: str | None
    mood_after: str | None
    draft: bool


@dataclass
class _PreviewPrepared:
    plain: str | None = None
    encrypted: bytes | None = None
    tokens: list[int] = field(default_factory=list)


@dataclass
class UPCreateResultDTO:
    id: uuid.UUID
    punts_awarded: int
    daily_cap_reached: bool
    esfera_counts: dict[str, int]


class UPService:
    """UP + Crisi create / read / patch / pin / redact orchestration."""

    def __init__(self, db: AsyncSession) -> None:
        self._db = db
        self._ups = UPRepository(db)
        self._crisi = UPCrisiRepository(db)
        self._feed = FeedRepository(db)
        self._esfera = EsferaRadiusRepository(db)
        self._outbox = OutboxRepository(db)
        self._uploads = UploadRepository(db)
        self._points = PointsService(db)
        self._audit = AuditEventRepository(db)
        # Consent decorator + Art-9 read logging (first real uses, Plan 019).
        self._consent_service = ConsentService(ConsentRepository(db))
        self._sca_log = SpecialCategoryAccessLogService(SpecialCategoryAccessLogRepository(db))

    @classmethod
    def from_session(cls, db: AsyncSession) -> UPService:
        return cls(db)

    # ── PREPARE helpers (encryption only — no DB writes) ─────────────────────────

    async def _prepare_tag(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID, tag: str | None
    ) -> tuple[bytes | None, list[int]]:
        if tag is None:
            return None, []
        encrypted = await encrypt_field_for_tenant(
            plaintext=tag.encode("utf-8"),
            tenant_id=tenant_id,
            column_key="UP.tag",
            row_id=up_id,
            db=self._db,
        )
        return encrypted, await search_tokens(f"{tag} {tag.replace('-', ' ')}", tenant_id, self._db)

    async def _prepare_note(
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        *,
        category: str,
        is_crisi: bool,
        note: str | None,
    ) -> _NotePrepared:
        """Option-H router. Art-9 → encrypt + tokenise (plain=None). Else plain."""
        if note is None:
            # No note: a non-Art-9 row stores note_plain=NULL? No — the CHECK requires
            # exactly one of (plain, encrypted) non-null. Empty-note UPs are allowed by
            # storing note_plain='' (non-null) for non-Art-9, or encrypting '' for Art-9.
            note = ""
        if _is_art9(category, is_crisi=is_crisi):
            enc = await encrypt_field_for_tenant(
                plaintext=note.encode("utf-8"),
                tenant_id=tenant_id,
                column_key="UP.note",
                row_id=up_id,
                db=self._db,
            )
            tokens = await search_tokens(note, tenant_id, self._db) if note else []
            return _NotePrepared(plain=None, encrypted=enc, tokens=tokens)
        return _NotePrepared(plain=note, encrypted=None, tokens=[])

    async def _prepare_crisi(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID, crisi: CrisiData
    ) -> _CrisiPrepared:
        """Crisi is ALWAYS Art-9: encrypt trigger + (optional) resolution, tokenise.

        A draft ("Acabar més tard") may still lack the trigger; completing it may not.
        """
        if not crisi.trigger_text and not crisi.draft:
            raise TriggerRequiredError()
        trigger_enc: bytes | None = None
        if crisi.trigger_text:
            trigger_enc = await encrypt_field_for_tenant(
                plaintext=crisi.trigger_text.encode("utf-8"),
                tenant_id=tenant_id,
                column_key="UPCrisi.trigger_text",
                row_id=up_id,
                db=self._db,
            )
        resolution_enc: bytes | None = None
        if crisi.resolution_text:
            resolution_enc = await encrypt_field_for_tenant(
                plaintext=crisi.resolution_text.encode("utf-8"),
                tenant_id=tenant_id,
                column_key="UPCrisi.resolution_text",
                row_id=up_id,
                db=self._db,
            )
        combined = f"{crisi.trigger_text or ''} {crisi.resolution_text or ''}".strip()
        tokens = await search_tokens(combined, tenant_id, self._db) if combined else []
        return _CrisiPrepared(
            trigger_encrypted=trigger_enc,
            resolution_encrypted=resolution_enc,
            tokens=tokens,
            duration_bucket=crisi.duration_bucket,
            mood_after=crisi.mood_after,
            draft=crisi.draft,
        )

    async def _prepare_preview(
        self,
        tenant_id: uuid.UUID,
        feed_entry_id: uuid.UUID,
        *,
        category: str,
        is_crisi: bool,
        note: str | None,
        note_tokens: list[int],
    ) -> _PreviewPrepared:
        """FeedEntry preview mirrors the UP's encryption posture (Option-H)."""
        preview = note[:_PREVIEW_LEN] if note else None
        if preview is None:
            return _PreviewPrepared()
        if _is_art9(category, is_crisi=is_crisi):
            enc = await encrypt_field_for_tenant(
                plaintext=preview.encode("utf-8"),
                tenant_id=tenant_id,
                column_key="FeedEntry.preview_text",
                row_id=feed_entry_id,
                db=self._db,
            )
            # Reuse the note tokens when the preview is a prefix of the note; recompute
            # only when truncation changed the last word boundary (cheap + correct).
            tokens = (
                note_tokens
                if note and len(note) <= _PREVIEW_LEN
                else await search_tokens(preview, tenant_id, self._db)
            )
            return _PreviewPrepared(plain=None, encrypted=enc, tokens=tokens)
        return _PreviewPrepared(plain=preview, encrypted=None, tokens=[])

    # ── create_up — PREPARE then PERSIST ─────────────────────────────────────────

    async def _preflight_up_attachments(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        upload_keys: list[str],
        *,
        allowed_contexts: frozenset[str],
    ) -> list[dict]:
        """Reject invalid references before encryption or any domain write."""
        if len(upload_keys) != len(set(upload_keys)):
            raise AttachmentOwnershipRejectedError()
        pending_uploads: list[dict] = []
        for upload_key in upload_keys:
            pending = await self._uploads.get_pending_by_key(tenant_id, upload_key)
            if (
                pending is None
                or pending["profile_id"] != profile_id
                or pending["context"] not in allowed_contexts
                or pending["expires_at"] is not None
                or pending["pipeline_status"] not in {"pending", "ready"}
                or pending["linked_up_id"] is not None
                or pending["linked_observation_id"] is not None
            ):
                raise AttachmentOwnershipRejectedError()
            pending_uploads.append(pending)
        return pending_uploads

    async def _assert_audio_attachment_limit(
        self,
        tenant_id: uuid.UUID,
        pending_uploads: list[dict],
    ) -> None:
        audio_count = sum(pending["context"] == CONTEXT_UP_AUDIO for pending in pending_uploads)
        if audio_count <= 1:
            return
        premium = await SubscriptionEntitlementReader().is_active(self._db, tenant_id)
        limit = 2 if premium else 1
        if audio_count > limit:
            raise AudioAttachmentLimitExceededError(limit)

    async def _link_up_attachments(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        up_id: uuid.UUID,
        upload_keys: list[str],
        *,
        allowed_contexts: frozenset[str],
    ) -> tuple[list[dict], set[str]]:
        """Atomically bind verified upload reservations and queue missing scans."""
        descriptors: list[dict] = []
        ready_mimes: set[str] = set()
        for position, upload_key in enumerate(upload_keys):
            linked = await self._uploads.link_up(
                tenant_id,
                upload_key,
                up_id,
                profile_id=profile_id,
                position=position,
                allowed_contexts=allowed_contexts,
            )
            if linked is None:
                raise AttachmentOwnershipRejectedError()
            descriptors.append({"upload_key": upload_key})
            if linked["pipeline_status"] == "ready":
                ready_mimes.add(str(linked["mime"]))
            if linked["pipeline_status"] == "pending":
                await self._outbox.insert_once(
                    tenant_id,
                    event_type="upload.scan_requested",
                    payload={
                        "upload_key": upload_key,
                        "context": linked["context"],
                        "tenant_id": str(tenant_id),
                        "up_id": str(up_id),
                    },
                    idempotency_key=uuid.uuid5(
                        tenant_id,
                        f"upload.scan_requested:{upload_key}",
                    ),
                )
        return descriptors, ready_mimes

    @requires_profile_consent("ups")
    async def create_up(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        user_id: uuid.UUID,
        data: UPCreateRequest,
    ) -> UPCreateResultDTO:
        """Single-TX UP (+ optional Crisi sidecar) create. No commit (router owns it).

        The @requires_profile_consent('ups') decorator raises 403 CONSENT_NOT_FOUND
        if there is no live 'ups' consent for this profile (FIRST REAL USE).
        """
        # Attachment cap (Q106 / API.md §8.6) — boundary validation before any work.
        if len(data.attachments) > MAX_ATTACHMENTS:
            raise AttachmentLimitExceededError(MAX_ATTACHMENTS)

        upload_keys = [attachment.upload_key for attachment in data.attachments]
        try:
            pending_uploads = await self._preflight_up_attachments(
                tenant_id,
                profile_id,
                upload_keys,
                allowed_contexts=frozenset(
                    {CONTEXT_UP_IMAGE, CONTEXT_UP_AUDIO, CONTEXT_UP_DOCUMENT}
                ),
            )
        except AttachmentOwnershipRejectedError as exc:
            raise AttachmentRejectedError() from exc
        await self._assert_audio_attachment_limit(tenant_id, pending_uploads)

        is_crisi = data.is_crisi
        # Pre-allocate ids so AAD (which binds row_id) is computed in PREPARE.
        up_id = uuid.uuid4()
        feed_entry_id = uuid.uuid4()

        # ── PREPARE: ALL encryption + tokenisation, ZERO DB writes ───────────────
        # If ANY of these raise KmsUnavailableError, we return 503 with no rows.
        note_prep = await self._prepare_note(
            tenant_id, up_id, category=data.category, is_crisi=is_crisi, note=data.note
        )
        tag_encrypted, tag_tokens = await self._prepare_tag(tenant_id, up_id, data.tag)
        crisi_prep: _CrisiPrepared | None = None
        if is_crisi:
            crisi_data = data.crisi or CrisiData()
            crisi_prep = await self._prepare_crisi(tenant_id, up_id, crisi_data)
        preview_prep = await self._prepare_preview(
            tenant_id,
            feed_entry_id,
            category=data.category,
            is_crisi=is_crisi,
            note=data.note,
            note_tokens=note_prep.tokens,
        )
        preview_prep.tokens = list(dict.fromkeys([*preview_prep.tokens, *tag_tokens]))

        # ── PERSIST: single TX, no commit ────────────────────────────────────────
        up = await self._ups.create(
            tenant_id,
            up_id=up_id,
            profile_id=profile_id,
            author_user_id=user_id,
            category=data.category,
            occurred_at=data.occurred_at,
            mood=data.mood,
            note_plain=note_prep.plain,
            note_encrypted=note_prep.encrypted,
            note_search_tokens=note_prep.tokens,
            tag_encrypted=tag_encrypted,
            tag_search_tokens=tag_tokens,
            attachments=[],
            is_crisi=is_crisi,
        )
        try:
            attachment_descriptors, ready_mimes = await self._link_up_attachments(
                tenant_id,
                profile_id,
                up.id,
                upload_keys,
                allowed_contexts=frozenset(
                    {CONTEXT_UP_IMAGE, CONTEXT_UP_AUDIO, CONTEXT_UP_DOCUMENT}
                ),
            )
        except AttachmentOwnershipRejectedError as exc:
            raise AttachmentRejectedError() from exc
        up.attachments = attachment_descriptors

        if is_crisi and crisi_prep is not None:
            await self._crisi.create(
                tenant_id,
                up_id=up.id,
                trigger_encrypted=crisi_prep.trigger_encrypted,
                resolution_encrypted=crisi_prep.resolution_encrypted,
                search_tokens=crisi_prep.tokens,
                duration_bucket=crisi_prep.duration_bucket,
                mood_after=crisi_prep.mood_after,
                draft=crisi_prep.draft,
            )

        await self._feed.write_entry(
            tenant_id,
            entity_type="up",
            entity_id=up.id,
            profile_id=profile_id,
            category=data.category,
            occurred_at=data.occurred_at,
            preview_plain=preview_prep.plain,
            preview_encrypted=preview_prep.encrypted,
            preview_search_tokens=preview_prep.tokens,
            # The preview AAD was bound to feed_entry_id in PREPARE — the row MUST
            # take that id or the Art-9 preview cannot be decrypted on read (Plan 020).
            entry_id=feed_entry_id,
            mood=data.mood,
            has_attachment=bool(ready_mimes),
            has_photo=any(mime.startswith("image/") for mime in ready_mimes),
            has_audio=any(mime.startswith("audio/") for mime in ready_mimes),
            is_crisi=is_crisi,
            crisi_draft=crisi_prep.draft if crisi_prep is not None else False,
        )

        await self._feed.refresh_up_media(tenant_id, up.id)
        await self._esfera.increment(tenant_id, profile_id, data.category)

        points = await self._points.award(tenant_id, user_id, profile_id, reference_id=up.id)

        # Primary outbox event — idempotency_key = the UP id (one event per create).
        await self._outbox.insert(
            tenant_id,
            event_type="up.crisi.created" if is_crisi else "up.created",
            payload={
                "up_id": str(up.id),
                "profile_id": str(profile_id),
                "tenant_id": str(tenant_id),
            },
            idempotency_key=up.id,
        )

        # save_to_arxiu sub-event (round-2 CRITICAL — NO app.document import).
        # Keyed by a fresh uuid so it does not collide with the primary key's UNIQUE.
        # Plan 023 drains this into a Document through the registered outbox handler.
        if data.save_to_arxiu:
            await self._outbox.insert(
                tenant_id,
                event_type="up.saved_to_arxiu_requested",
                payload={
                    "up_id": str(up.id),
                    "profile_id": str(profile_id),
                    "tenant_id": str(tenant_id),
                    # Plan 023 drainer needs the author for the Document's users FK.
                    "author_user_id": str(user_id),
                    "arxiu_section": data.arxiu_section or "altres",
                },
                idempotency_key=uuid.uuid4(),
            )

        await self._audit.append(
            NewAuditEvent(
                event_kind=(
                    AuditEventKind.UP_CRISI_CREATED if is_crisi else AuditEventKind.UP_CREATED
                ),
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up",
                entity_id=up.id,
                meta={"profile_id": str(profile_id), "category": data.category},
            )
        )
        await self._db.flush()

        return UPCreateResultDTO(
            id=up.id,
            punts_awarded=points.awarded,
            daily_cap_reached=points.cap_reached,
            esfera_counts=await self._esfera.get_counts(tenant_id, profile_id),
        )

    # ── create_activa_up — ActivaUpWriterPort impl (Plan 021 cross-domain bridge) ─

    async def create_activa_up(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        author_user_id: uuid.UUID,
        linked_exercici_attempt_id: uuid.UUID | None,
        linked_assignment_exercise_attempt_id: uuid.UUID | None,
        upload_key: str,
        proof_kind: str,
        note: str | None,
        monetisation_grace: bool = False,
        award_points: bool = True,
    ) -> uuid.UUID:
        """Write an Activa-sourced UP (category='activa') + FeedEntry + EsferaRadius
        + points(+1, uncapped) + outbox, in the CALLER's session (no commit).

        This is the implementation of app.shared.ports.ActivaUpWriterPort. ExerciciService
        (app.activa) calls it through the Port so app.activa never imports app.up; the
        composition root injects this UPService instance.

        category='activa' is non-Art-9, so the note is plaintext and EsferaRadius
        increments ONCE for the 'activa' bucket (round-2 CRITICAL — NO loop over the
        plan's tematiques; esfera_radius is keyed by (profile_id, esfera_slug) and
        'activa' is a single bucket).

        The injected session is the request session shared with ExerciciService — it is
        the same object as self._db (deps.py constructs both on one session), so the
        repositories already bound to self._db write into the right TX.
        """
        if session is not self._db:
            raise RuntimeError("ActivaUpWriterPort must share the caller's session")
        if (linked_exercici_attempt_id is None) == (linked_assignment_exercise_attempt_id is None):
            raise ValueError("an Activa UP must link exactly one attempt type")
        await self._preflight_up_attachments(
            tenant_id,
            profile_id,
            [upload_key],
            allowed_contexts=frozenset({CONTEXT_ACTIVA_PROOF}),
        )

        up_id = uuid.uuid4()
        feed_entry_id = uuid.uuid4()
        occurred_at = datetime.now(UTC)

        # PREPARE: activa is non-Art-9 → note_plain (no encryption / KMS dependency).
        note_prep = await self._prepare_note(
            tenant_id, up_id, category="activa", is_crisi=False, note=note
        )
        preview_prep = await self._prepare_preview(
            tenant_id,
            feed_entry_id,
            category="activa",
            is_crisi=False,
            note=note,
            note_tokens=note_prep.tokens,
        )

        # PERSIST (no commit — the router owns the single commit).
        up = await self._ups.create(
            tenant_id,
            up_id=up_id,
            profile_id=profile_id,
            author_user_id=author_user_id,
            category="activa",
            occurred_at=occurred_at,
            mood=None,
            note_plain=note_prep.plain,
            note_encrypted=note_prep.encrypted,
            note_search_tokens=note_prep.tokens,
            attachments=[],
            is_crisi=False,
            linked_exercici_attempt_id=linked_exercici_attempt_id,
            linked_assignment_exercise_attempt_id=linked_assignment_exercise_attempt_id,
            monetisation_grace=monetisation_grace,
        )
        attachment_descriptors, ready_mimes = await self._link_up_attachments(
            tenant_id,
            profile_id,
            up.id,
            [upload_key],
            allowed_contexts=frozenset({CONTEXT_ACTIVA_PROOF}),
        )
        attachment_descriptors[0]["kind"] = proof_kind
        up.attachments = attachment_descriptors

        await self._feed.write_entry(
            tenant_id,
            entity_type="up",
            entity_id=up.id,
            profile_id=profile_id,
            category="activa",
            occurred_at=occurred_at,
            preview_plain=preview_prep.plain,
            preview_encrypted=preview_prep.encrypted,
            preview_search_tokens=preview_prep.tokens,
            entry_id=feed_entry_id,
            has_attachment=bool(ready_mimes),
            has_photo=any(mime.startswith("image/") for mime in ready_mimes),
            has_audio=any(mime.startswith("audio/") for mime in ready_mimes),
            is_activa_completion=True,
            activa_attempt_id=linked_assignment_exercise_attempt_id,
        )

        await self._feed.refresh_up_media(tenant_id, up.id)

        # round-2 CRITICAL: increment the 'activa' esfera bucket EXACTLY ONCE.
        await self._esfera.increment(tenant_id, profile_id, "activa")

        # Activa points: +1, NO daily cap (branch by event — not the +5 cap-25 path).
        if award_points:
            await self._points.award_activa_exercise(
                tenant_id, author_user_id, profile_id, reference_id=up.id
            )

        await self._outbox.insert(
            tenant_id,
            event_type="up.created",
            payload={
                "up_id": str(up.id),
                "profile_id": str(profile_id),
                "tenant_id": str(tenant_id),
                "source": "activa",
            },
            idempotency_key=up.id,
        )

        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_CREATED,
                tenant_id=tenant_id,
                actor_user_id=author_user_id,
                entity_type="up",
                entity_id=up.id,
                meta={"profile_id": str(profile_id), "category": "activa"},
            )
        )
        await self._db.flush()
        return up.id

    # ── UpBackLinkPort impl (Plan 023 attach-arxiu cross-domain bridge) ───────────

    async def get_attachment_for_arxiu(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        attachment_index: int,
        user_id: uuid.UUID | None = None,
    ) -> dict:
        """Validate the UP + its attachment for attach-arxiu (app.shared.ports impl).

        Returns {'profile_id', 'upload_key', 'already_linked'}. Raises UPNotFoundError
        if the UP is absent/wrong-tenant, AttachmentIndexError if there is no attachment
        at the index. app.document never imports app.up — this port is the bridge.
        """
        if session is not self._db:
            raise RuntimeError("UpBackLinkPort must share the caller's session")
        from app.up.errors import AttachmentIndexError

        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        if user_id is not None:
            await assert_up_role(self._db, tenant_id, user_id, up_id, "view_only")
        if attachment_index < 0:
            raise AttachmentIndexError()
        attachment = await self._uploads.get_linked_up_attachment(
            tenant_id, up.id, attachment_index
        )
        if attachment is None:
            raise AttachmentIndexError()
        return {
            "profile_id": up.profile_id,
            # DocumentService re-checks this staging key's authoritative verdict and
            # resolves only its server-owned clean candidate for persistence.
            "upload_key": str(attachment["upload_key"]),
            "already_linked": up.linked_document_id is not None,
        }

    async def set_linked_document(
        self,
        session: AsyncSession,
        *,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        document_id: uuid.UUID,
    ) -> None:
        """Write UP.linked_document_id (only when NULL). No commit (app.shared.ports impl)."""
        if session is not self._db:
            raise RuntimeError("UpBackLinkPort must share the caller's session")
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        if up.linked_document_id is None:
            up.linked_document_id = document_id
            await self._db.flush()

    # ── read (Art-9 access logged + decrypted) ───────────────────────────────────

    async def get_up_decrypted(
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        *,
        user_id: uuid.UUID,
        purpose: str = "family_member_view",
    ) -> dict:
        """Fetch + decrypt a UP for the response. For Art-9 UPs (salut/emocions or
        is_crisi) write a special_category_access_log row BEFORE returning (API §6.7).
        """
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()

        await assert_up_role(self._db, tenant_id, user_id, up_id, "view_only")

        art9 = _is_art9(up.category, is_crisi=up.is_crisi)
        if art9 or up.tag_encrypted is not None:
            await self._sca_log.log_access(
                tenant_id=tenant_id,
                resource_kind="up",
                resource_id=up.id,
                purpose=purpose,
                user_id=user_id,
            )

        note: str | None
        if up.note_encrypted is not None:
            note = (
                await decrypt_field_for_tenant(
                    ciphertext=up.note_encrypted,
                    tenant_id=tenant_id,
                    column_key="UP.note",
                    row_id=up.id,
                    db=self._db,
                )
            ).decode("utf-8")
        else:
            note = up.note_plain

        tag = None
        if up.tag_encrypted is not None:
            tag = (
                await decrypt_field_for_tenant(
                    ciphertext=up.tag_encrypted,
                    tenant_id=tenant_id,
                    column_key="UP.tag",
                    row_id=up.id,
                    db=self._db,
                )
            ).decode("utf-8")

        crisi: dict | None = None
        if up.is_crisi:
            sidecar = await self._crisi.get_by_up_id(tenant_id, up.id)
            if sidecar is not None:
                trigger, resolution = await self._decrypt_crisi_texts(tenant_id, sidecar)
                crisi = {
                    "trigger_text": trigger,
                    "resolution_text": resolution,
                    "duration_bucket": sidecar.duration_bucket,
                    "mood_after": sidecar.mood_after,
                    "draft": sidecar.draft,
                    "user_redacted_at": sidecar.user_redacted_at,
                }

        return {
            "id": up.id,
            "profile_id": up.profile_id,
            "category": up.category,
            "category_editable": not (
                up.linked_exercici_attempt_id or up.linked_assignment_exercise_attempt_id
            ),
            "occurred_at": up.occurred_at,
            "mood": up.mood,
            "note": note or None,
            "tag": tag,
            "is_pinned": up.is_pinned,
            "is_crisi": up.is_crisi,
            "crisi": crisi,
            **await self._uploads.get_up_attachment_summary(tenant_id, up.id),
            "created_at": up.created_at,
            "former_author": former_author(up.author_erased_at, up.former_author_first_name),
            "author": (
                await load_family_authors(self._db, tenant_id, user_id, [up.author_user_id])
            ).of(up.author_user_id, up.author_erased_at, up.former_author_first_name),
        }

    async def create_attachment_download_grant(  # feed-write-exempt: read grant is not feed content
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        attachment_index: int,
        *,
        user_id: uuid.UUID,
    ) -> dict:
        """Mint a 60-second grant for one clean, linked UP attachment."""
        from datetime import timedelta

        from app.uploads.constants import PRESIGN_GET_TTL_SECONDS
        from app.uploads.storage import get_object_storage

        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        await assert_up_role(self._db, tenant_id, user_id, up_id, "view_only")

        if attachment_index < 0:
            raise UPNotFoundError()
        attachment = await self._uploads.get_ready_for_up_attachment(
            tenant_id,
            up_id,
            attachment_index,
        )
        if attachment is None:
            raise UPNotFoundError()

        if _is_art9(up.category, is_crisi=up.is_crisi):
            await self._sca_log.log_access(
                tenant_id=tenant_id,
                resource_kind="up",
                resource_id=up.id,
                purpose="family_member_view",
                user_id=user_id,
            )

        ttl = min(PRESIGN_GET_TTL_SECONDS, 60)
        return {
            "download_url": get_object_storage().generate_presigned_get(
                str(attachment["upload_key"]), expires_in=ttl
            ),
            "mime": str(attachment["mime"]),
            "size_bytes": int(attachment["verified_size_bytes"]),
            "expires_at": datetime.now(UTC) + timedelta(seconds=ttl),
        }

    # ── patch ─────────────────────────────────────────────────────────────────

    async def patch_up(
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        user_id: uuid.UUID,
        data: UPPatchRequest,
    ) -> dict:
        """Patch mood / note / category. is_crisi is immutable (422).

        Category change across the Art-9 boundary (round-2 HIGH) re-encrypts-or-
        decrypts the note, swaps which column is null, recomputes search tokens, and
        emits up.category_reclassified. Same handling for the FeedEntry preview.
        """
        if data.is_crisi is not None:
            raise IsCrisiImmutableError()

        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()

        await assert_up_role(self._db, tenant_id, user_id, up_id, "edit")
        await lock_profile_for_write(self._db, tenant_id, up.profile_id)

        crisi_completed = False
        if data.crisi is not None:
            crisi_completed = await self._patch_crisi(tenant_id, up, data.crisi)

        new_category = data.category if data.category is not None else up.category
        category_changed = new_category != up.category
        if category_changed and (
            up.linked_exercici_attempt_id or up.linked_assignment_exercise_attempt_id
        ):
            raise AppError(
                code="UP_CATEGORY_FIXED",
                status_code=422,
                message="Completed exercise UPs keep their Activa category.",
            )
        crossed_art9_boundary = _is_art9(up.category, is_crisi=up.is_crisi) != _is_art9(
            new_category, is_crisi=up.is_crisi
        )

        # Resolve the effective note plaintext (new value, or the existing one).
        if data.note is not None:
            note_plaintext: str | None = data.note
            note_provided = True
        else:
            note_provided = False
            note_plaintext = await self._current_note_plaintext(tenant_id, up)

        # PREPARE re-encryption (no writes yet) when note OR Art-9-ness changes.
        must_rewrite_note = note_provided or crossed_art9_boundary
        tag_provided = "tag" in data.model_fields_set
        tag_encrypted, tag_tokens = (
            await self._prepare_tag(tenant_id, up.id, data.tag)
            if tag_provided
            else (up.tag_encrypted, up.tag_search_tokens)
        )
        note_prep: _NotePrepared | None = None
        preview_prep: _PreviewPrepared | None = None
        if must_rewrite_note:
            note_prep = await self._prepare_note(
                tenant_id, up.id, category=new_category, is_crisi=up.is_crisi, note=note_plaintext
            )
        if must_rewrite_note or tag_provided:
            feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up.id)
            if feed is not None:
                preview_prep = await self._prepare_preview(
                    tenant_id,
                    feed.id,
                    category=new_category,
                    is_crisi=up.is_crisi,
                    note=note_plaintext,
                    note_tokens=note_prep.tokens if note_prep else up.note_search_tokens,
                )
                preview_prep.tokens = list(dict.fromkeys([*preview_prep.tokens, *tag_tokens]))

        # PERSIST
        if data.mood is not None:
            up.mood = data.mood
        if category_changed:
            up.category = new_category
        if tag_provided:
            up.tag_encrypted = tag_encrypted
            up.tag_search_tokens = tag_tokens
        if must_rewrite_note and note_prep is not None:
            up.note_plain = note_prep.plain
            up.note_encrypted = note_prep.encrypted
            up.note_search_tokens = note_prep.tokens
        up.updated_at = datetime.now(UTC)
        await self._db.flush()

        # Keep the denormalised FeedEntry coherent (preview/category on a note or
        # Art-9 change; mood always, since the card renders mood from FeedEntry alone).
        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up.id)
        if feed is not None:
            if preview_prep is not None:
                feed.preview_plain = preview_prep.plain
                feed.preview_encrypted = preview_prep.encrypted
                feed.preview_search_tokens = preview_prep.tokens
            if category_changed:
                feed.category = new_category
            if data.mood is not None:
                feed.mood = data.mood
            await self._db.flush()

        if crossed_art9_boundary:
            await self._audit.append(
                NewAuditEvent(
                    event_kind=AuditEventKind.UP_CATEGORY_RECLASSIFIED,
                    tenant_id=tenant_id,
                    actor_user_id=user_id,
                    entity_type="up",
                    entity_id=up.id,
                    meta={"to_category": new_category},
                )
            )
        else:
            await self._audit.append(
                NewAuditEvent(
                    event_kind=AuditEventKind.UP_UPDATED,
                    tenant_id=tenant_id,
                    actor_user_id=user_id,
                    entity_type="up",
                    entity_id=up.id,
                    meta={"crisi_completed": True} if crisi_completed else None,
                )
            )
        await self._db.flush()
        return await self.get_up_decrypted(tenant_id, up.id, user_id=user_id)

    async def _decrypt_crisi_texts(
        self, tenant_id: uuid.UUID, sidecar
    ) -> tuple[str | None, str | None]:

        texts: list[str | None] = []
        for column_key, ciphertext in (
            ("UPCrisi.trigger_text", sidecar.trigger_text),
            ("UPCrisi.resolution_text", sidecar.resolution_text),
        ):
            if ciphertext is None:
                texts.append(None)
                continue
            plaintext = await decrypt_field_for_tenant(
                ciphertext=ciphertext,
                tenant_id=tenant_id,
                column_key=column_key,
                row_id=sidecar.up_id,
                db=self._db,
            )
            texts.append(plaintext.decode("utf-8") or None)
        return texts[0], texts[1]

    async def _patch_crisi(self, tenant_id: uuid.UUID, up, patch: CrisiPatchData) -> bool:
        """Merge the patch into the sidecar; returns True when a draft was completed."""
        if not up.is_crisi:
            raise NotACrisiError()
        sidecar = await self._crisi.get_by_up_id(tenant_id, up.id)
        if sidecar is None:
            raise NotACrisiError()
        moved = patch.occurred_at is not None and patch.occurred_at != up.occurred_at
        if moved and not sidecar.draft:
            raise CrisiMomentFixedError()
        trigger, resolution = await self._decrypt_crisi_texts(tenant_id, sidecar)
        merged = CrisiData(
            trigger_text=patch.trigger_text if patch.trigger_text is not None else trigger,
            resolution_text=(
                patch.resolution_text if patch.resolution_text is not None else resolution
            ),
            duration_bucket=(
                patch.duration_bucket
                if patch.duration_bucket is not None
                else cast(DurationBucket | None, sidecar.duration_bucket)
            ),
            mood_after=patch.mood_after
            if patch.mood_after is not None
            else cast(Mood | None, sidecar.mood_after),
            draft=patch.draft if patch.draft is not None else sidecar.draft,
        )
        prepared = await self._prepare_crisi(tenant_id, up.id, merged)
        completed = sidecar.draft and not prepared.draft
        sidecar.trigger_text = prepared.trigger_encrypted
        sidecar.resolution_text = prepared.resolution_encrypted
        sidecar.search_tokens = prepared.tokens
        sidecar.duration_bucket = prepared.duration_bucket
        sidecar.mood_after = prepared.mood_after
        sidecar.draft = prepared.draft
        sidecar.updated_at = datetime.now(UTC)
        if moved:
            up.occurred_at = patch.occurred_at
        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up.id)
        if feed is not None:
            feed.crisi_draft = prepared.draft
            if moved:
                feed.occurred_at = patch.occurred_at
        await self._db.flush()
        return completed

    async def _current_note_plaintext(self, tenant_id: uuid.UUID, up) -> str | None:
        if up.note_encrypted is not None:
            return (
                await decrypt_field_for_tenant(
                    ciphertext=up.note_encrypted,
                    tenant_id=tenant_id,
                    column_key="UP.note",
                    row_id=up.id,
                    db=self._db,
                )
            ).decode("utf-8")
        return up.note_plain

    # ── delete (soft, 7-day recovery) ────────────────────────────────────────────

    async def delete_up(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID, user_id: uuid.UUID
    ) -> uuid.UUID:
        """Soft-delete + tombstone the feed row. Returns the profile_id (so the
        router can bust the home cache post-commit)."""
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        await assert_up_role(self._db, tenant_id, user_id, up_id, "edit")
        await lock_profile_for_write(self._db, tenant_id, up.profile_id)
        up = await self._ups.soft_delete(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        # Tombstone the denormalised feed row so the unified feed hides it.
        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up_id)
        if feed is not None:
            feed.deleted_at = datetime.now(UTC)
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_DELETED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up",
                entity_id=up_id,
            )
        )
        # Plan 026: emit up.deleted so the AI domain (via the outbox drainer's topic handler)
        # can soft-delete insights citing this UP + flush their Redis caches. The cross-domain
        # cascade is bridged via the OUTBOX — app.up does NOT import app.ai (domain isolation).
        await self._outbox.insert(
            tenant_id,
            event_type="up.deleted",
            payload={
                "up_id": str(up_id),
                "profile_id": str(up.profile_id),
                "tenant_id": str(tenant_id),
            },
            idempotency_key=uuid.uuid4(),
        )
        await self._db.flush()
        return up.profile_id

    # ── recently deleted + restore ───────────────────────────────────────────────

    async def list_deleted_ups(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID, user_id: uuid.UUID
    ) -> list[dict]:
        """A profile's UPs still inside the recovery window. Needs the role that can
        delete (edit), since every row offers a restore."""
        await assert_profile_role(self._db, tenant_id, user_id, profile_id, "edit")
        now = datetime.now(UTC)
        blocked = await self._restore_block(tenant_id, profile_id, lock=False)
        blocked_reason = RESTORE_BLOCK_REASONS[blocked.code] if blocked is not None else None
        items: list[dict] = []
        for up, feed in await self._ups.list_recoverable(tenant_id, profile_id, now=now):
            deleted_at = cast(datetime, up.deleted_at)
            restore_until = deleted_at + UP_RECOVERY_WINDOW
            preview: str | None
            if feed.preview_encrypted is not None:
                await self._sca_log.log_access(
                    tenant_id=tenant_id,
                    resource_kind="up",
                    resource_id=up.id,
                    purpose="family_member_view",
                    user_id=user_id,
                )
                preview = (
                    await decrypt_field_for_tenant(
                        ciphertext=feed.preview_encrypted,
                        tenant_id=tenant_id,
                        column_key="FeedEntry.preview_text",
                        row_id=feed.id,
                        db=self._db,
                    )
                ).decode("utf-8") or None
            else:
                preview = feed.preview_plain or None
            items.append(
                {
                    "id": up.id,
                    "profile_id": up.profile_id,
                    "category": up.category,
                    "occurred_at": up.occurred_at,
                    "mood": up.mood,
                    "is_crisi": up.is_crisi,
                    "preview": preview,
                    "has_attachment": feed.has_attachment,
                    "deleted_at": deleted_at,
                    "restore_until": restore_until,
                    "days_left": max(1, -((now - restore_until) // timedelta(days=1))),
                    "restore_blocked_reason": blocked_reason,
                }
            )
        return items

    async def _restore_block(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID, *, lock: bool
    ) -> AppError | None:
        """Why a deleted UP of this profile cannot come back now, if it cannot.

        A restore puts a UP back into processing, so it answers to the profile's state
        today, not the day of the delete: the profile must be open to writes (no
        at-18 handoff lock, no unanswered adult consent, no erasure request) and its
        'ups' consent must be live, exactly as creating the UP would require.
        """
        try:
            if lock:
                await lock_profile_for_write(self._db, tenant_id, profile_id)
            else:
                closed = await read_profile_write_block(self._db, tenant_id, profile_id)
                if closed is not None:
                    raise closed
            await self._consent_service.assert_consent(profile_id=profile_id, scope="ups")
        except AppError as exc:
            if exc.code not in RESTORE_BLOCK_REASONS:
                raise
            return exc
        return None

    async def restore_up(self, tenant_id: uuid.UUID, up_id: uuid.UUID, user_id: uuid.UUID) -> dict:
        """Undo a family member's delete inside the recovery window: the UP and its
        feed row come back in one TX. The Crisi sidecar, attachments, points and
        Esfera counts were never touched by the delete, so they need no repair.
        A repeat on a live UP is a no-op (``was_already``)."""
        up = await self._ups.get_by_id_including_deleted(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        await assert_profile_role(
            self._db, tenant_id, user_id, up.profile_id, "edit", captured_at=up.created_at
        )
        if up.deleted_at is None:
            return {"id": up.id, "profile_id": up.profile_id, "was_already": True}

        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up_id)
        # Only a family delete tombstones the feed row; a moderation take-down hides
        # it instead and is not the family's to undo.
        if feed is None or feed.deleted_at is None or not feed.visible_to_family:
            raise UPNotFoundError()
        deleted_at = up.deleted_at
        if deleted_at + UP_RECOVERY_WINDOW <= datetime.now(UTC):
            raise UPRestoreWindowExpiredError()
        blocked = await self._restore_block(tenant_id, up.profile_id, lock=True)
        if blocked is not None:
            raise blocked

        up.deleted_at = None
        feed.deleted_at = None
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_RESTORED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up",
                entity_id=up_id,
                meta={"deleted_at": deleted_at.isoformat()},
            )
        )
        await self._outbox.insert(
            tenant_id,
            event_type="up.restored",
            payload={
                "up_id": str(up_id),
                "profile_id": str(up.profile_id),
                "tenant_id": str(tenant_id),
            },
            idempotency_key=uuid.uuid4(),
        )
        await self._db.flush()
        return {"id": up.id, "profile_id": up.profile_id, "was_already": False}

    # ── pin / unpin (idempotent — round-2 HIGH) ──────────────────────────────────

    async def pin_memory(self, tenant_id: uuid.UUID, up_id: uuid.UUID, user_id: uuid.UUID) -> dict:
        """Idempotent: a repeat pin returns {is_pinned:True, was_already:True}, 200."""
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        await assert_up_role(self._db, tenant_id, user_id, up_id, "edit")
        await lock_profile_for_write(self._db, tenant_id, up.profile_id)
        if up.is_pinned:
            return {"is_pinned": True, "was_already": True, "profile_id": up.profile_id}
        await self._ups.set_pinned(tenant_id, up_id, pinned=True)
        # Mirror onto the denormalised feed row — the Memòries grid reads is_pinned
        # from FeedEntry alone (no join to ups).
        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up_id)
        if feed is not None:
            feed.is_pinned = True
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_PINNED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up",
                entity_id=up_id,
            )
        )
        await self._db.flush()
        return {"is_pinned": True, "was_already": False, "profile_id": up.profile_id}

    async def unpin_memory(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID, user_id: uuid.UUID
    ) -> dict:
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None:
            raise UPNotFoundError()
        await assert_up_role(self._db, tenant_id, user_id, up_id, "edit")
        await lock_profile_for_write(self._db, tenant_id, up.profile_id)
        if not up.is_pinned:
            return {"is_pinned": False, "was_already": True, "profile_id": up.profile_id}
        await self._ups.set_pinned(tenant_id, up_id, pinned=False)
        feed = await self._feed.get_by_entity(tenant_id, entity_type="up", entity_id=up_id)
        if feed is not None:
            feed.is_pinned = False
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_UNPINNED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up",
                entity_id=up_id,
            )
        )
        await self._db.flush()
        return {"is_pinned": False, "was_already": False, "profile_id": up.profile_id}

    # ── redact crisi (selective erasure — wave-1 HIGH) ───────────────────────────

    async def redact_crisi(
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        user_id: uuid.UUID,
        *,
        reclassified_as: str | None = None,
    ) -> None:
        """Blank the encrypted trigger/resolution + clear tokens + set
        user_redacted_at, KEEPING duration_bucket / mood_after for the aggregate
        patron pipeline. Audited as up_crisi.redacted.
        """
        up = await self._ups.get_by_id(tenant_id, up_id)
        if up is None or not up.is_crisi:
            raise NotACrisiError()
        await assert_up_role(self._db, tenant_id, user_id, up_id, "edit")
        await lock_profile_for_write(self._db, tenant_id, up.profile_id)
        crisi = await self._crisi.redact(tenant_id, up_id, reclassified_as=reclassified_as)
        if crisi is None:
            raise NotACrisiError()
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.UP_CRISI_REDACTED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="up_crisi",
                entity_id=up_id,
                meta={"reclassified_as": reclassified_as} if reclassified_as else None,
            )
        )
        await self._db.flush()
