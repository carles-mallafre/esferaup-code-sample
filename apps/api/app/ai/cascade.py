"""UP-delete → insight invalidation cascade (Plan 026 Step 15).

When a UP is soft- or hard-deleted, every insight citing it is no longer trustworthy (its
evidence base changed). This module soft-deletes those insights + flushes their Redis SWR
caches + emits AI_INSIGHT_INVALIDATED.

CROSS-DOMAIN BRIDGE via the OUTBOX (NOT an import): app.up emits up.deleted; the outbox
drainer's topic handler (registered in app.tasks.outbox_drainer) calls
cascade_invalidate_for_up(). This module reads the SHARED insights + insight_up_links tables
by raw SQL — it does NOT import app.up (domain isolation; import-linter enforces
app.ai ↛ app.up/observation/document).

Runs on the drainer's SYSTEM (BYPASSRLS) session — the cascade is a background job, so
make_system_session is the correct session type (Plan 015 A9).
"""

from __future__ import annotations

import contextlib
import uuid

import structlog
from sqlalchemy import text

logger = structlog.get_logger(__name__)


async def cascade_invalidate_for_up(db: object, *, tenant_id: uuid.UUID, up_id: uuid.UUID) -> int:
    """Soft-delete + Redis-flush + audit every live insight citing ``up_id``. Returns the count.

    Idempotent: an insight already soft-deleted is skipped (the WHERE deleted_at IS NULL filter).
    The caller (the outbox drainer) commits the TX.
    """
    from sqlalchemy.ext.asyncio import AsyncSession

    from app.ai.schema import insight_cache_key
    from app.audit.event_kinds import AuditEventKind
    from app.audit.repository import AuditEventRepository
    from app.audit.schemas import NewAuditEvent

    session: AsyncSession = db  # type: ignore[assignment]

    # A delete undone before this event drained must not strip a live UP's insights.
    restored = (
        await session.execute(
            text("SELECT 1 FROM ups WHERE id = :uid AND tenant_id = :tid AND deleted_at IS NULL"),
            {"uid": str(up_id), "tid": str(tenant_id)},
        )
    ).first()
    if restored is not None:
        return 0

    rows = (
        (
            await session.execute(
                text(
                    "SELECT i.id, i.profile_id, i.prompt_id, i.prompt_version "
                    "FROM insights i JOIN insight_up_links l ON l.insight_id = i.id "
                    "WHERE l.up_id = :uid AND i.tenant_id = :tid AND i.deleted_at IS NULL"
                ),
                {"uid": str(up_id), "tid": str(tenant_id)},
            )
        )
        .mappings()
        .all()
    )

    if not rows:
        return 0

    audit = AuditEventRepository(session)
    from app.core.redis import get_redis

    redis = get_redis()
    try:
        for row in rows:
            insight_id = uuid.UUID(str(row["id"]))
            await session.execute(
                text("UPDATE insights SET deleted_at = now() WHERE id = :iid"),
                {"iid": str(insight_id)},
            )
            # Flush the SWR cache key (prompt_version is in the key).
            if row["prompt_id"] and row["prompt_version"]:
                key = insight_cache_key(
                    tenant_id=tenant_id,
                    profile_id=uuid.UUID(str(row["profile_id"])),
                    prompt_id=row["prompt_id"],
                    prompt_version=row["prompt_version"],
                )
                with contextlib.suppress(Exception):  # cache flush best-effort; DB is truth
                    await redis.delete(key)
            await audit.append(
                NewAuditEvent(
                    event_kind=AuditEventKind.AI_INSIGHT_INVALIDATED,
                    tenant_id=tenant_id,
                    entity_type="insight",
                    entity_id=insight_id,
                    meta={"reason": "source_up_deleted", "up_id": str(up_id)},
                )
            )
    finally:
        await redis.aclose()

    logger.info("ai_insights_invalidated", count=len(rows), up_id=str(up_id))
    return len(rows)


async def cascade_restore_for_up(db: object, *, tenant_id: uuid.UUID, up_id: uuid.UUID) -> int:
    """Bring back the insights a UP delete removed, once that UP is restored.

    Only ``cascade_invalidate_for_up`` soft-deletes insights, so a soft-deleted insight
    citing ``up_id`` was removed by the delete of one of its cited UPs. It returns only
    when EVERY cited UP is live again and no live insight with the same content hash
    took its place (uq_insight_content_hash). Idempotent; the caller commits.
    """
    from sqlalchemy.ext.asyncio import AsyncSession

    from app.ai.schema import insight_cache_key
    from app.audit.event_kinds import AuditEventKind
    from app.audit.repository import AuditEventRepository
    from app.audit.schemas import NewAuditEvent
    from app.core.redis import get_redis

    session: AsyncSession = db  # type: ignore[assignment]

    rows = (
        (
            await session.execute(
                text(
                    "SELECT i.id, i.profile_id, i.prompt_id, i.prompt_version "
                    "FROM insights i JOIN insight_up_links l ON l.insight_id = i.id "
                    "WHERE l.up_id = :uid AND i.tenant_id = :tid AND i.deleted_at IS NOT NULL "
                    "AND NOT EXISTS ("
                    "  SELECT 1 FROM insight_up_links other "
                    "  LEFT JOIN ups cited ON cited.id = other.up_id "
                    "  WHERE other.insight_id = i.id "
                    "    AND (cited.id IS NULL OR cited.deleted_at IS NOT NULL)) "
                    "AND NOT EXISTS ("
                    "  SELECT 1 FROM insights live "
                    "  WHERE live.tenant_id = i.tenant_id AND live.profile_id = i.profile_id "
                    "    AND live.insight_hash = i.insight_hash AND live.deleted_at IS NULL)"
                ),
                {"uid": str(up_id), "tid": str(tenant_id)},
            )
        )
        .mappings()
        .all()
    )
    if not rows:
        return 0

    audit = AuditEventRepository(session)
    redis = get_redis()
    try:
        for row in rows:
            insight_id = uuid.UUID(str(row["id"]))
            await session.execute(
                text("UPDATE insights SET deleted_at = NULL WHERE id = :iid"),
                {"iid": str(insight_id)},
            )
            if row["prompt_id"] and row["prompt_version"]:
                key = insight_cache_key(
                    tenant_id=tenant_id,
                    profile_id=uuid.UUID(str(row["profile_id"])),
                    prompt_id=row["prompt_id"],
                    prompt_version=row["prompt_version"],
                )
                with contextlib.suppress(Exception):  # cache flush best-effort; DB is truth
                    await redis.delete(key)
            await audit.append(
                NewAuditEvent(
                    event_kind=AuditEventKind.AI_INSIGHT_RESTORED,
                    tenant_id=tenant_id,
                    entity_type="insight",
                    entity_id=insight_id,
                    meta={"reason": "source_up_restored", "up_id": str(up_id)},
                )
            )
    finally:
        await redis.aclose()

    logger.info("ai_insights_restored", count=len(rows), up_id=str(up_id))
    return len(rows)
