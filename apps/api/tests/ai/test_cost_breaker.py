"""Plan 026 Step 6 — the cost circuit breaker.

Hard ceiling → auto-flip the tenant flag off + AI_BUDGET_EXHAUSTED audit. Burn-rate breaker →
flip flag off. Platform cap → global kill. FAIL-CLOSED on Redis error.
"""

from __future__ import annotations

import pytest
from sqlalchemy import text

from app.ai.cost_breaker import check_and_charge, estimate_cost_eur, estimate_tokens
from app.ai.gate import is_ai_enabled, set_tenant_ai_flag

pytestmark = pytest.mark.asyncio


async def test_estimate_helpers() -> None:
    """Token + cost estimates are monotonic + positive."""
    assert estimate_tokens({"a": "x" * 400}) >= 100
    assert estimate_cost_eur(1000, 500) > 0


async def test_cost_hard_ceiling_flips_flag_and_audits(
    family_ctx: dict, redis_flush: None, monkeypatch
) -> None:
    """Exceeding the monthly cap auto-flips the tenant flag off + emits AI_BUDGET_EXHAUSTED."""
    from app.config import settings as settings_mod

    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]
    # Tiny cap so a single charge breaches it.
    monkeypatch.setattr(settings_mod.settings, "ai_tenant_monthly_budget_eur", 0.0000001)
    await set_tenant_ai_flag(tenant_id, enabled=True)
    assert await is_ai_enabled(tenant_id) is True

    allowed = await check_and_charge(
        db, tenant_id=tenant_id, estimated_input_tokens=5000, estimated_output_tokens=1000
    )
    assert allowed is False
    # Flag flipped off.
    assert await is_ai_enabled(tenant_id) is False
    # AI_BUDGET_EXHAUSTED audit emitted.
    count = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.budget_exhausted'"
            ),
            {"tid": str(tenant_id)},
        )
    ).scalar_one()
    assert count >= 1


async def test_cost_burn_rate_breaker_flips_flag(
    family_ctx: dict, redis_flush: None, monkeypatch
) -> None:
    """A 60s burn above 3x baseline flips the flag off (manual unblock)."""
    from app.config import settings as settings_mod

    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]
    # Generous monthly cap (so the monthly ceiling does not trip first) but a tiny burn baseline.
    monkeypatch.setattr(settings_mod.settings, "ai_tenant_monthly_budget_eur", 1000.0)
    monkeypatch.setattr(settings_mod.settings, "ai_platform_monthly_budget_eur", 100000.0)
    monkeypatch.setattr(settings_mod.settings, "ai_burn_rate_baseline_eur", 0.00000001)
    await set_tenant_ai_flag(tenant_id, enabled=True)

    allowed = await check_and_charge(
        db, tenant_id=tenant_id, estimated_input_tokens=5000, estimated_output_tokens=1000
    )
    assert allowed is False
    assert await is_ai_enabled(tenant_id) is False


async def test_cost_within_budget_allows(family_ctx: dict, redis_flush: None) -> None:
    """A normal charge under the (default) caps returns True and keeps the flag on."""
    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]
    await set_tenant_ai_flag(tenant_id, enabled=True)
    allowed = await check_and_charge(
        db, tenant_id=tenant_id, estimated_input_tokens=500, estimated_output_tokens=200
    )
    assert allowed is True
    assert await is_ai_enabled(tenant_id) is True


async def test_cost_fail_closed_on_redis_error(family_ctx: dict, monkeypatch) -> None:
    """A Redis error during the charge denies the call (cannot meter → deny)."""
    from unittest.mock import patch

    from redis.exceptions import ConnectionError as RedisConnectionError

    class _BoomRedis:
        def pipeline(self):
            raise RedisConnectionError("down")

        async def aclose(self):
            return None

    with patch("app.core.redis.get_redis", return_value=_BoomRedis()):
        allowed = await check_and_charge(
            family_ctx["db"], tenant_id=family_ctx["tenant_id"], estimated_input_tokens=100
        )
    assert allowed is False
