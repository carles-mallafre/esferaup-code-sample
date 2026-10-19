"""UP + Crisi request/response schemas (Plan 019).

`extra="forbid"` on every request model rejects client-declared server-owned
fields (balance_after, punts_awarded, …) — the elmetodo `balance_after` anti-pattern.

The Crisi block is stored internally under the up_crisi / is_crisi identifiers. The
user-facing 'moment difícil' COPY rename is a frontend concern (Plan 042); the
backend keeps neutral, non-alarming error codes (TRIGGER_REQUIRED, …).
"""

from __future__ import annotations

import unicodedata
import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

from app.schemas.common import ContentAuthor, FormerAuthor

UPCategory = Literal[
    "casa", "escola", "emocions", "esport", "salut", "nutricio", "descans", "activa"
]
Mood = Literal["happy", "love", "sad", "angry", "spark"]
DurationBucket = Literal["lt5", "five_to_15", "fifteen_to_30", "gt30"]
ArxiuSection = Literal["salut", "escola", "legal", "altres"]

# Max attachments per UP (Q106 resolved 2026-05-24 — API.md §8.6).
MAX_ATTACHMENTS = 5


def _normalize_tag(value: str) -> str:
    value = unicodedata.normalize("NFC", value.strip())
    if (
        not value
        or not any(char.isalnum() for char in value)
        or not all(char.isalnum() or char in "-'\u2019·" for char in value)
    ):
        raise ValueError("Use one word or a hyphenated word for the tag")
    return value


UPTag = Annotated[str, Field(max_length=60), AfterValidator(_normalize_tag)]


class CrisiData(BaseModel):
    """Crisi sidecar payload (Art-9 by definition — always encrypted)."""

    model_config = ConfigDict(extra="forbid")

    trigger_text: str | None = Field(default=None, max_length=4000)
    resolution_text: str | None = Field(default=None, max_length=4000)
    duration_bucket: DurationBucket | None = None
    mood_after: Mood | None = None
    draft: bool = False


class CrisiPatchData(BaseModel):
    """PATCH /v1/ups/{id} `crisi`: absent fields keep their stored value.

    `draft=false` completes an "Acabar més tard" draft, which then needs a trigger.
    `occurred_at` moves the crisis's moment while it is still a draft; a completed
    crisis keeps its moment.
    """

    model_config = ConfigDict(extra="forbid")

    occurred_at: datetime | None = None
    trigger_text: str | None = Field(default=None, max_length=4000)
    resolution_text: str | None = Field(default=None, max_length=4000)
    duration_bucket: DurationBucket | None = None
    mood_after: Mood | None = None
    draft: bool | None = None


class CrisiResponse(BaseModel):
    """Decrypted Crisi sidecar on GET/PATCH /v1/ups/{id} (Art-9 read is logged)."""

    trigger_text: str | None = None
    resolution_text: str | None = None
    duration_bucket: str | None = None
    mood_after: str | None = None
    draft: bool = False
    user_redacted_at: datetime | None = None


class UPAttachmentRequest(BaseModel):
    """Reference one upload reservation; all file metadata is server-owned."""

    model_config = ConfigDict(extra="forbid")

    upload_key: str = Field(min_length=1, max_length=500)


class UPAttachmentResponse(BaseModel):
    """A clean attachment. Pending or quarantined bytes are never returned."""

    attachment_index: int = Field(ge=0)
    upload_key: str
    mime: str
    size_bytes: int


class UPAttachmentDownloadResponse(BaseModel):
    """Short-lived authenticated read grant. Never exposes the storage key."""

    download_url: str
    mime: str
    size_bytes: int
    expires_at: datetime


class UPCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: UPCategory
    occurred_at: datetime
    mood: Mood | None = None
    note: str | None = Field(default=None, max_length=8000)
    tag: UPTag | None = None
    attachments: list[UPAttachmentRequest] = Field(default_factory=list, max_length=MAX_ATTACHMENTS)
    is_crisi: bool = False
    crisi: CrisiData | None = None
    # save_to_arxiu wiring (Q47): when true, emit an outbox sub-event that Plan 023
    # drains into a Document — NO cross-domain import here.
    save_to_arxiu: bool = False
    arxiu_section: ArxiuSection | None = None

    @model_validator(mode="after")
    def arxiu_requires_attachment(self) -> UPCreateRequest:
        if self.save_to_arxiu and not self.attachments:
            raise ValueError("save_to_arxiu requires at least one attachment")
        return self


class CrisiCreateRequest(BaseModel):
    """Convenience body for POST /v1/profiles/{id}/crisis — forces is_crisi=True
    and defaults category='emocions'. Fields map to CrisiData; non-alarming."""

    model_config = ConfigDict(extra="forbid")

    occurred_at: datetime
    category: UPCategory = "emocions"
    note: str | None = Field(default=None, max_length=8000)
    trigger_text: str | None = Field(default=None, max_length=4000)
    resolution_text: str | None = Field(default=None, max_length=4000)
    duration_bucket: DurationBucket | None = None
    mood_after: Mood | None = None
    draft: bool = False
    save_to_arxiu: bool = False
    arxiu_section: ArxiuSection | None = None


class UPPatchRequest(BaseModel):
    """PATCH /v1/ups/{id}. is_crisi is NOT patchable (round-2 CRITICAL —
    IS_CRISI_IMMUTABLE_AFTER_CREATE); flipping it would orphan/strand the sidecar."""

    model_config = ConfigDict(extra="forbid")

    category: UPCategory | None = None
    mood: Mood | None = None
    note: str | None = Field(default=None, max_length=8000)
    tag: UPTag | None = None
    is_crisi: bool | None = Field(
        default=None,
        description="Rejected with 422 IS_CRISI_IMMUTABLE_AFTER_CREATE. Soft-delete + recreate.",
    )
    crisi: CrisiPatchData | None = Field(
        default=None,
        description="Update the Crisi sidecar; `draft: false` completes a saved draft.",
    )


class CrisiRedactRequest(BaseModel):
    """Blank the encrypted Crisi text while keeping aggregates. Optionally
    reclassify ('this wasn't crisi, it was a sensory event / transition')."""

    model_config = ConfigDict(extra="forbid")

    reclassified_as: str | None = Field(default=None, max_length=32)


class UPCreateResult(BaseModel):
    """201 body — lets the client celebrate without a second round-trip."""

    id: uuid.UUID
    punts_awarded: int
    daily_cap_reached: bool
    esfera_counts: dict[str, int]


class CrisiCreateResult(BaseModel):
    """201 body for the Crisi convenience endpoint."""

    id: uuid.UUID
    up_id: uuid.UUID
    punts_awarded: int
    daily_cap_reached: bool
    esfera_counts: dict[str, int]


class UPResponse(BaseModel):
    """GET /v1/ups/{id} — note decrypted via the service for Art-9 rows."""

    id: uuid.UUID
    profile_id: uuid.UUID
    category: str
    category_editable: bool = True
    occurred_at: datetime
    mood: str | None = None
    note: str | None = None
    tag: str | None = None
    is_pinned: bool = False
    is_crisi: bool = False
    crisi: CrisiResponse | None = None
    attachments: list[UPAttachmentResponse] = Field(default_factory=list)
    attachments_pending: bool = False
    created_at: datetime
    former_author: FormerAuthor | None = Field(
        default=None,
        description="Set when the adult who wrote it has erased their account.",
    )
    author: ContentAuthor | None = Field(
        default=None,
        description="The adult of the family who wrote it, for adults of the same family only.",
    )


class DeletedUPItem(BaseModel):
    """One row of the "recently deleted" list."""

    id: uuid.UUID
    profile_id: uuid.UUID
    category: str
    occurred_at: datetime
    mood: str | None = None
    is_crisi: bool = False
    preview: str | None = None
    has_attachment: bool = False
    deleted_at: datetime
    restore_until: datetime
    days_left: int = Field(ge=1, description="Whole days left to restore, rounded up.")
    restore_blocked_reason: (
        Literal[
            "consent_revoked",
            "profile_migrating",
            "awaiting_adult_consent",
            "erasure_requested",
        ]
        | None
    ) = Field(
        default=None,
        description=(
            "Set when a restore would be refused now: the profile's 'ups' consent is "
            "revoked, or the profile is closed to writes."
        ),
    )


class DeletedUPListResponse(BaseModel):
    items: list[DeletedUPItem]


class UPRestoreResult(BaseModel):
    """Idempotent restore result: was_already True when the UP was not deleted."""

    id: uuid.UUID
    profile_id: uuid.UUID
    was_already: bool


class PinResult(BaseModel):
    """Idempotent pin/unpin result (round-2 HIGH): was_already True on a repeat."""

    is_pinned: bool
    was_already: bool
