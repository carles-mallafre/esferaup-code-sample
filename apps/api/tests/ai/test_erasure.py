"""Plan 026 — Art-17 erasure includes the AI tables + Redis flush.

The erasure cascade hard-deletes insights / insight_dismissals / ai_consent_grants / patterns;
the erase task flushes the tenant's AI Redis keys. This test asserts the cascade removes the
AI rows (the Redis flush helper is unit-tested separately — the Celery task uses a system
session that does not see the test SAVEPOINT, so we drive the cascade directly here).
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import text

from app.ai.insight_service import InsightService
from app.gdpr.erasure_order import ERASURE_ORDER_SET
from tests.factories.up import UPFactory

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _relax_k_anon(monkeypatch):
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 1)


async def test_ai_tables_in_erasure_order() -> None:
    """The AI tables are all covered by the Art-17 cascade order (or cascade via FK)."""
    for table in ("insights", "insight_dismissals", "ai_consent_grants", "patterns"):
        assert table in ERASURE_ORDER_SET


async def test_erasure_cascade_deletes_ai_rows(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """perform_erasure_cascade hard-deletes the tenant's insights + consent grants."""
    from app.ai.consent_service import AIConsentService

    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]

    # Seed an insight + a consent grant.
    for _ in range(2):
        await UPFactory(
            db,
            tenant_id=tenant_id,
            profile_id=family_ctx["profile_id"],
            author_user_id=family_ctx["admin_id"],
            category="casa",
        )
    await db.flush()
    await InsightService(db).compute(
        tenant_id,
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    await AIConsentService(db).grant(
        tenant_id, family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"]
    )
    await db.flush()

    # Pre-condition: rows exist.
    pre_insights = (
        await db.execute(
            text("SELECT count(*) FROM insights WHERE tenant_id = :t"), {"t": str(tenant_id)}
        )
    ).scalar_one()
    assert pre_insights >= 1

    # Run the cascade directly against the test session (BYPASSRLS not needed — the test
    # session is the superuser local role).
    from app.gdpr.erasure import perform_erasure_cascade

    # The cascade erases a family that asked for it.
    await db.execute(
        text("UPDATE tenants SET deleted_at = now() - interval '31 days' WHERE id = :t"),
        {"t": str(tenant_id)},
    )
    await perform_erasure_cascade(tenant_id, db)

    for table in ("insights", "ai_consent_grants"):
        remaining = (
            await db.execute(
                text(f"SELECT count(*) FROM {table} WHERE tenant_id = :t"),
                {"t": str(tenant_id)},
            )
        ).scalar_one()
        assert remaining == 0, f"{table} not erased"


async def test_flush_ai_redis_keys(redis_flush: None) -> None:
    """Tenant erasure removes the AI flag, budget, and insight cache keys."""
    from app.core.redis import get_redis
    from app.tasks.gdpr_tasks import _flush_tenant_redis_keys

    tenant_id = str(uuid.uuid4())
    redis = get_redis()
    try:
        await redis.set(f"ai:flag:{tenant_id}", "true")
        await redis.set(f"ai_budget:{tenant_id}:2026-05", "1.0")
        await redis.set(f"ai:insight:{tenant_id}:p:insight_family_weekly:v1", "{}")
        await _flush_tenant_redis_keys(tenant_id)
        assert await redis.get(f"ai:flag:{tenant_id}") is None
        assert await redis.get(f"ai_budget:{tenant_id}:2026-05") is None
        assert await redis.get(f"ai:insight:{tenant_id}:p:insight_family_weekly:v1") is None
    finally:
        await redis.aclose()
