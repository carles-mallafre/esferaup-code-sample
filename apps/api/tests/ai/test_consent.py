"""Plan 026 Step 1 — per-profile AI consent grant + revoke.

Grant is idempotent; revoke writes revoked_at + flushes the tenant Redis flag + audits.
"""

from __future__ import annotations

import pytest
from sqlalchemy import text

from app.ai.consent_service import AIConsentService
from app.ai.gate import is_ai_enabled

pytestmark = pytest.mark.asyncio


async def test_grant_then_has_consent(family_ctx: dict, redis_flush: None) -> None:
    db = family_ctx["db"]
    tid, pid, admin = family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    svc = AIConsentService(db)
    await svc.grant(tid, pid, actor_user_id=admin)
    assert await svc.has_consent(tid, pid) is True


async def test_grant_idempotent(family_ctx: dict, redis_flush: None) -> None:
    db = family_ctx["db"]
    svc = AIConsentService(db)
    id1 = await svc.grant(
        family_ctx["tenant_id"], family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"]
    )
    id2 = await svc.grant(
        family_ctx["tenant_id"], family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"]
    )
    assert id1 == id2  # no duplicate grant


async def test_revoke_flushes_flag_and_audits(family_ctx: dict, redis_flush: None) -> None:
    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]
    svc = AIConsentService(db)
    await svc.grant(tenant_id, family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"])
    # Grant sets the runtime flag on.
    assert await is_ai_enabled(tenant_id) is True

    revoked = await svc.revoke(
        tenant_id, family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"]
    )
    assert revoked is True
    # Flag flushed immediately.
    assert await is_ai_enabled(tenant_id) is False

    # revoked_at set on the row.
    revoked_at = (
        await db.execute(
            text(
                "SELECT revoked_at FROM ai_consent_grants WHERE tenant_id = :tid "
                "AND profile_id = :pid"
            ),
            {"tid": str(tenant_id), "pid": str(family_ctx["profile_id"])},
        )
    ).scalar_one()
    assert revoked_at is not None

    # Both consent audit events present.
    granted = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.consent.granted'"
            ),
            {"tid": str(tenant_id)},
        )
    ).scalar_one()
    revoked_audit = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.consent.revoked'"
            ),
            {"tid": str(tenant_id)},
        )
    ).scalar_one()
    assert granted >= 1
    assert revoked_audit >= 1


async def test_revoke_without_grant_is_idempotent(family_ctx: dict, redis_flush: None) -> None:
    """Revoking with no active grant returns False but still ensures the flag is off (fail-safe)."""
    db = family_ctx["db"]
    revoked = await AIConsentService(db).revoke(
        family_ctx["tenant_id"], family_ctx["profile_id"], actor_user_id=family_ctx["admin_id"]
    )
    assert revoked is False
    assert await is_ai_enabled(family_ctx["tenant_id"]) is False
