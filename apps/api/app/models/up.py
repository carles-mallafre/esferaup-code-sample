"""UP (family-authored capture) and UPCrisi sidecar ORM models."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import ARRAY, ENUM, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


class UP(Base, TimestampMixin):
    __tablename__ = "ups"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="CASCADE"), nullable=False
    )
    profile_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False
    )
    author_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    # Set when the author's account was erased while the family kept the content (0525):
    # the user reference is gone and only their first name, if known, stays.
    author_erased_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    former_author_first_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(
        ENUM(
            "casa",
            "escola",
            "emocions",
            "esport",
            "salut",
            "nutricio",
            "descans",
            "activa",
            name="upcategory",
            create_type=False,
        ),
        nullable=False,
    )
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    occurred_at_tz: Mapped[str | None] = mapped_column(Text, nullable=True)
    mood: Mapped[str | None] = mapped_column(
        ENUM("happy", "love", "sad", "angry", "spark", name="moodtype", create_type=False),
        nullable=True,
    )
    note_plain: Mapped[str | None] = mapped_column(Text, nullable=True)
    note_encrypted: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    tag_encrypted: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    tag_search_tokens: Mapped[list] = mapped_column(
        ARRAY(Integer), nullable=False, server_default="{}"
    )
    note_search_tokens: Mapped[list] = mapped_column(
        ARRAY(Integer), nullable=False, server_default="{}"
    )
    attachments: Mapped[list[dict] | None] = mapped_column(JSONB, nullable=True)
    is_pinned: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    memory_suppressed: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    pattern_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("patterns.id", ondelete="SET NULL"), nullable=True
    )
    is_crisi: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    linked_exercici_attempt_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("exercici_attempts.id", ondelete="SET NULL"),
        nullable=True,
    )
    linked_assignment_exercise_attempt_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("activa_exercise_attempts.id", ondelete="SET NULL"),
        nullable=True,
    )
    linked_document_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("documents.id", ondelete="SET NULL"),
        nullable=True,
    )
    # Plan 021 round-2 HIGH: set true for an Activa UP written while the tenant
    # subscription is past_due (grace allowed) — finance reconciles these.
    monetisation_grace: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false"
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    __table_args__ = (
        CheckConstraint(
            "(note_plain IS NULL) <> (note_encrypted IS NULL)",
            name="note_exactly_one",
        ),
        CheckConstraint(
            "category NOT IN ('salut', 'emocions') OR note_plain IS NULL",
            name="note_art9_must_be_encrypted",
        ),
        CheckConstraint(
            "num_nonnulls(linked_exercici_attempt_id, linked_assignment_exercise_attempt_id) <= 1",
            name="ck_up_single_activa_attempt",
        ),
        CheckConstraint(
            "linked_assignment_exercise_attempt_id IS NULL OR category = 'activa'",
            name="ck_up_assignment_attempt_category",
        ),
    )


class UPCrisi(Base):
    """Sidecar of UP (one-to-one). PK is also the FK to ups.id."""

    __tablename__ = "up_crisi"

    up_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("ups.id", ondelete="CASCADE"),
        primary_key=True,
    )
    trigger_text: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    resolution_text: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    search_tokens: Mapped[list] = mapped_column(ARRAY(Integer), nullable=False, server_default="{}")
    duration_bucket: Mapped[str | None] = mapped_column(
        ENUM(
            "lt5", "five_to_15", "fifteen_to_30", "gt30", name="durationbucket", create_type=False
        ),
        nullable=True,
    )
    mood_after: Mapped[str | None] = mapped_column(
        ENUM("happy", "love", "sad", "angry", "spark", name="moodtype", create_type=False),
        nullable=True,
    )
    draft: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    # Wave-1 HIGH (selective erasure): set when a parent blanks trigger_text +
    # resolution_text while KEEPING the duration_bucket / mood_after aggregates.
    user_redacted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Wave-1 HIGH (reclassification): neutral label, e.g. 'sensory_event' /
    # 'transition' — "this wasn't crisi". Not Art-9 on its own (a category, not the
    # painful narrative), so stored as plaintext varchar.
    reclassified_as: Mapped[str | None] = mapped_column(String(32), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default="now()"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default="now()"
    )
