"""UP + UPCrisi repositories (Plan 019).

TenantScopedRepository: tenant_id is the first positional arg on every public
async method (Plan 009 lint A2 + runtime guard). NO session.commit() here — the
service flushes; the router commits (single-TX invariant, API.md §11.1).

Option-H note split (Q36): the SERVICE decides note_plain vs note_encrypted +
note_search_tokens and passes both; the repo writes exactly what it is given.
The DB CHECK constraints (note_exactly_one + note_art9_must_be_encrypted) are the
last line of defence.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.models.feed import FeedEntry
from app.models.up import UP, UPCrisi
from app.repositories.base import TenantScopedRepository

# OutboxRepository moved to a neutral shared module (app.repositories.outbox_repository)
# so non-UP domains (e.g. Activa) can use it without crossing an import wall. Re-exported
# here for the Plan 019 import path (app.services.up_service imports it from here).
from app.repositories.outbox_repository import OutboxRepository

# A soft-deleted UP can be restored for this long; ``reapers.reap_ups`` hard-deletes
# on the same boundary.
UP_RECOVERY_WINDOW = timedelta(days=7)

__all__ = ["UP_RECOVERY_WINDOW", "OutboxRepository", "UPCrisiRepository", "UPRepository"]


class UPRepository(TenantScopedRepository):
    """UP CRUD (tenant-scoped). The note columns are written verbatim from the
    service's Option-H routing decision."""

    model = UP

    async def create(
        self,
        tenant_id: uuid.UUID,
        *,
        profile_id: uuid.UUID,
        author_user_id: uuid.UUID,
        category: str,
        occurred_at: datetime,
        mood: str | None,
        note_plain: str | None,
        note_encrypted: bytes | None,
        note_search_tokens: list[int],
        attachments: list | None,
        is_crisi: bool,
        up_id: uuid.UUID | None = None,
        linked_exercici_attempt_id: uuid.UUID | None = None,
        linked_assignment_exercise_attempt_id: uuid.UUID | None = None,
        monetisation_grace: bool = False,
        tag_encrypted: bytes | None = None,
        tag_search_tokens: list[int] | None = None,
    ) -> UP:
        self._check_tenant(tenant_id)
        up = UP(
            id=up_id or uuid.uuid4(),
            tenant_id=tenant_id,
            profile_id=profile_id,
            author_user_id=author_user_id,
            category=category,
            occurred_at=occurred_at,
            mood=mood,
            note_plain=note_plain,
            note_encrypted=note_encrypted,
            note_search_tokens=note_search_tokens,
            tag_encrypted=tag_encrypted,
            tag_search_tokens=tag_search_tokens or [],
            attachments=attachments if attachments is not None else [],
            is_crisi=is_crisi,
            linked_exercici_attempt_id=linked_exercici_attempt_id,
            linked_assignment_exercise_attempt_id=linked_assignment_exercise_attempt_id,
            monetisation_grace=monetisation_grace,
        )
        self.db.add(up)
        await self.db.flush()
        return up

    async def get_by_id(self, tenant_id: uuid.UUID, up_id: uuid.UUID) -> UP | None:
        """Live UP (deleted_at IS NULL) for (tenant, id), else None."""
        self._check_tenant(tenant_id)
        result = await self.db.execute(
            select(UP).where(
                UP.id == up_id,
                UP.tenant_id == tenant_id,
                UP.deleted_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    async def soft_delete(self, tenant_id: uuid.UUID, up_id: uuid.UUID) -> UP | None:
        """7-day-recovery soft delete (accepted_mvp §20.0): set deleted_at."""
        self._check_tenant(tenant_id)
        up = await self.get_by_id(tenant_id, up_id)
        if up is None:
            return None
        up.deleted_at = datetime.now(UTC)
        await self.db.flush()
        return up

    async def get_by_id_including_deleted(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID
    ) -> UP | None:
        self._check_tenant(tenant_id)
        result = await self.db.execute(select(UP).where(UP.id == up_id, UP.tenant_id == tenant_id))
        return result.scalar_one_or_none()

    async def list_recoverable(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        now: datetime,
        limit: int = 100,
    ) -> list[tuple[UP, FeedEntry]]:
        """UPs a family member deleted inside the recovery window, newest deletion
        first. A moderation take-down hides the feed row without tombstoning it, so
        requiring a tombstoned, still-visible feed row keeps taken-down UPs out."""
        self._check_tenant(tenant_id)
        result = await self.db.execute(
            select(UP, FeedEntry)
            .join(
                FeedEntry,
                (FeedEntry.tenant_id == UP.tenant_id)
                & (FeedEntry.entity_type == "up")
                & (FeedEntry.entity_id == UP.id),
            )
            .where(
                UP.tenant_id == tenant_id,
                UP.profile_id == profile_id,
                UP.deleted_at.is_not(None),
                UP.deleted_at > now - UP_RECOVERY_WINDOW,
                FeedEntry.deleted_at.is_not(None),
                FeedEntry.visible_to_family.is_(True),
            )
            .order_by(UP.deleted_at.desc(), UP.id.desc())
            .limit(limit)
        )
        return [(row[0], row[1]) for row in result.all()]

    async def set_pinned(
        self, tenant_id: uuid.UUID, up_id: uuid.UUID, *, pinned: bool
    ) -> UP | None:
        self._check_tenant(tenant_id)
        up = await self.get_by_id(tenant_id, up_id)
        if up is None:
            return None
        up.is_pinned = pinned
        await self.db.flush()
        return up

    async def list_by_profile(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        limit: int = 25,
    ) -> list[UP]:
        """Pagination scaffold — the full filtered feed query lives in Plan 020."""
        self._check_tenant(tenant_id)
        result = await self.db.execute(
            select(UP)
            .where(
                UP.tenant_id == tenant_id,
                UP.profile_id == profile_id,
                UP.deleted_at.is_(None),
            )
            .order_by(UP.occurred_at.desc(), UP.id.desc())
            .limit(limit)
        )
        return list(result.scalars().all())


class UPCrisiRepository(TenantScopedRepository):
    """UPCrisi sidecar CRUD.

    The sidecar PK is up_id (also the FK to ups.id). It has no tenant_id column
    of its own (tenant scope flows through the parent UP's FK + RLS), so the
    tenant_id arg here is a guard-only first positional that is validated against
    the context but not used in the WHERE clause.
    """

    # No `model` (PK is up_id, not id) — methods are explicit.

    async def create(
        self,
        tenant_id: uuid.UUID,
        *,
        up_id: uuid.UUID,
        trigger_encrypted: bytes | None,
        resolution_encrypted: bytes | None,
        search_tokens: list[int],
        duration_bucket: str | None,
        mood_after: str | None,
        draft: bool = False,
    ) -> UPCrisi:
        self._check_tenant(tenant_id)
        crisi = UPCrisi(
            up_id=up_id,
            trigger_text=trigger_encrypted,
            resolution_text=resolution_encrypted,
            search_tokens=search_tokens,
            duration_bucket=duration_bucket,
            mood_after=mood_after,
            draft=draft,
        )
        self.db.add(crisi)
        await self.db.flush()
        return crisi

    async def get_by_up_id(self, tenant_id: uuid.UUID, up_id: uuid.UUID) -> UPCrisi | None:
        self._check_tenant(tenant_id)
        result = await self.db.execute(select(UPCrisi).where(UPCrisi.up_id == up_id))
        return result.scalar_one_or_none()

    async def redact(
        self,
        tenant_id: uuid.UUID,
        up_id: uuid.UUID,
        *,
        reclassified_as: str | None = None,
    ) -> UPCrisi | None:
        """Selective erasure (wave-1 HIGH): blank the encrypted text fields + clear
        search tokens + set user_redacted_at, while KEEPING duration_bucket and
        mood_after (the non-identifying aggregates the patron pipeline needs).
        Optionally records a neutral reclassification label.
        """
        self._check_tenant(tenant_id)
        crisi = await self.get_by_up_id(tenant_id, up_id)
        if crisi is None:
            return None
        crisi.trigger_text = None
        crisi.resolution_text = None
        crisi.search_tokens = []
        crisi.user_redacted_at = datetime.now(UTC)
        if reclassified_as is not None:
            crisi.reclassified_as = reclassified_as
        await self.db.flush()
        return crisi
