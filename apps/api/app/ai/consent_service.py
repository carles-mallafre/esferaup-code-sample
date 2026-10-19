"""AIConsentService — per-profile AI consent grant + revoke (Plan 026 Step 1).

AI Patrons are an Art-22 profiling activity on minors → consent is explicit + per-profile +
revocable. The grant row (ai_consent_grants, owned by Plan 010) links a profile to the AI
feature. DELETE /v1/ai-consent revokes it: writes revoked_at + flushes the tenant Redis flag
immediately + emits the AI_CONSENT_REVOKED audit (so a revoke stops AI within one request,
not one cache cycle).

Consent grant/revoke may be performed by a family admin OR (Plan 014 child-objection) the
14+ data subject. The role check lives in the router; this service owns the persistence +
audit + Redis flush.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.event_kinds import AuditEventKind
from app.audit.repository import AuditEventRepository
from app.audit.schemas import NewAuditEvent
from app.models.tenant import AIConsentGrant

logger = structlog.get_logger(__name__)

_AI_FEATURE = "ai"


class AIConsentService:
    """Grant + revoke per-profile AI consent. Service owns persistence + audit + Redis flush."""

    def __init__(self, db: AsyncSession) -> None:
        self._db = db
        self._audit = AuditEventRepository(db)

    async def _active_grant(self, tenant_id: UUID, profile_id: UUID) -> AIConsentGrant | None:
        result = await self._db.execute(
            select(AIConsentGrant).where(
                AIConsentGrant.tenant_id == tenant_id,
                AIConsentGrant.profile_id == profile_id,
                AIConsentGrant.feature == _AI_FEATURE,
                AIConsentGrant.revoked_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    async def has_consent(self, tenant_id: UUID, profile_id: UUID) -> bool:
        """True if a live (non-revoked) AI consent grant exists for the profile."""
        return (await self._active_grant(tenant_id, profile_id)) is not None

    async def grant(self, tenant_id: UUID, profile_id: UUID, *, actor_user_id: UUID) -> UUID:
        """Idempotently grant AI consent for a profile. Sets the tenant Redis flag on."""
        existing = await self._active_grant(tenant_id, profile_id)
        if existing is not None:
            return existing.id

        grant = AIConsentGrant(
            id=uuid4(),
            tenant_id=tenant_id,
            profile_id=profile_id,
            feature=_AI_FEATURE,
            granted_at=datetime.now(UTC),
        )
        self._db.add(grant)
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.AI_CONSENT_GRANTED,
                tenant_id=tenant_id,
                actor_user_id=actor_user_id,
                entity_type="profile",
                entity_id=profile_id,
            )
        )
        await self._db.flush()

        # Best-effort: set the runtime flag so the gate lets the tenant through (still subject
        # to the DPIA feature flag, which stays off at MVP — so this is a no-op until launch).
        from app.ai.gate import set_tenant_ai_flag

        await set_tenant_ai_flag(tenant_id, enabled=True)
        return grant.id

    async def revoke(self, tenant_id: UUID, profile_id: UUID, *, actor_user_id: UUID) -> bool:
        """Revoke AI consent: write revoked_at + flush the tenant Redis flag + audit.

        Returns True if a grant was revoked, False if there was nothing to revoke (idempotent).
        """
        grant = await self._active_grant(tenant_id, profile_id)
        revoked = grant is not None
        if grant is not None:
            grant.revoked_at = datetime.now(UTC)

        # Flush the runtime flag IMMEDIATELY (fail-safe — a revoke must stop AI now). We do
        # this even when there was no grant row (defence-in-depth: ensure AI is off).
        from app.ai.gate import set_tenant_ai_flag

        await set_tenant_ai_flag(tenant_id, enabled=False)

        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.AI_CONSENT_REVOKED,
                tenant_id=tenant_id,
                actor_user_id=actor_user_id,
                entity_type="profile",
                entity_id=profile_id,
            )
        )
        await self._db.flush()
        logger.info("ai_consent_revoked", tenant_id=str(tenant_id), revoked=revoked)
        return revoked
