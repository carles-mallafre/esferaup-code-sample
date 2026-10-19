"""Plan 026 — the dual gate: FAIL-CLOSED flag + DPIA 503 + premium + kill switch.

These are the cardinal safety tests. The anti-pattern this closes is "failing OPEN on Redis":
is_ai_enabled MUST return False on ANY Redis error, never True.
"""

from __future__ import annotations

import uuid
from unittest.mock import patch

import pytest
from redis.exceptions import ConnectionError as RedisConnectionError

from app.ai.gate import (
    AiPipelineError,
    AiPremiumRequiredError,
    assert_ai_enabled,
    assert_ai_premium,
    engage_global_kill,
    is_ai_enabled,
    set_tenant_ai_flag,
)
from app.gdpr.feature_flags import FeatureFlagDisabledError
from tests.ai.conftest import enable_ai_runtime_flag, insert_premium_subscription

pytestmark = pytest.mark.asyncio


async def test_flag_fail_closed_on_redis_error(redis_flush: None) -> None:
    """is_ai_enabled returns False when Redis raises ConnectionError (never fail open)."""
    tenant_id = uuid.uuid4()

    class _BoomRedis:
        async def get(self, *a, **k):
            raise RedisConnectionError("redis down")

        async def aclose(self):
            return None

    with patch("app.core.redis.get_redis", return_value=_BoomRedis()):
        assert await is_ai_enabled(tenant_id) is False


async def test_flag_false_on_cache_miss(redis_flush: None) -> None:
    """A missing Redis flag → False (default-deny)."""
    assert await is_ai_enabled(uuid.uuid4()) is False


async def test_flag_true_only_when_set(redis_flush: None) -> None:
    """The flag is True ONLY when ai:flag:{tenant} == 'true'."""
    tenant_id = uuid.uuid4()
    await set_tenant_ai_flag(tenant_id, enabled=True)
    assert await is_ai_enabled(tenant_id) is True
    await set_tenant_ai_flag(tenant_id, enabled=False)
    assert await is_ai_enabled(tenant_id) is False


async def test_kill_switch_overrides_tenant_flag(redis_flush: None) -> None:
    """The global kill switch forces False even when the tenant flag is on (checked first)."""
    tenant_id = uuid.uuid4()
    await set_tenant_ai_flag(tenant_id, enabled=True)
    assert await is_ai_enabled(tenant_id) is True

    await engage_global_kill(reason="test")
    assert await is_ai_enabled(tenant_id) is False


async def test_kill_switch_fail_closed_on_redis_error(redis_flush: None) -> None:
    """A Redis error during the kill-switch check is treated as KILLED (deny)."""
    from app.ai.gate import is_global_kill_active

    class _BoomRedis:
        async def get(self, *a, **k):
            raise RedisConnectionError("redis down")

        async def aclose(self):
            return None

    with patch("app.core.redis.get_redis", return_value=_BoomRedis()):
        assert await is_global_kill_active() is True


async def test_dpia_gate_503_when_feature_off(family_ctx: dict, redis_flush: None) -> None:
    """assert_ai_enabled raises FEATURE_FLAG_DISABLED at MVP (feature_ai_enabled=False)."""
    db = family_ctx["db"]
    tenant_id = family_ctx["tenant_id"]
    # Even with the runtime flag set, the DPIA feature flag is off → 503.
    await enable_ai_runtime_flag(tenant_id)
    with pytest.raises(FeatureFlagDisabledError) as exc:
        await assert_ai_enabled(db, tenant_id)
    assert exc.value.code == "FEATURE_FLAG_DISABLED"
    assert exc.value.status_code == 503


async def test_runtime_tenant_enable_fails_closed_when_production_ner_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A tenant DB flag cannot bypass the production privacy-boundary startup posture."""
    from app.ai.pseudonymise import PseudonymisationUnavailableError
    from app.gdpr.feature_flags import FeatureFlagService

    async def _feature_on(*_args, **_kwargs) -> None:
        return None

    async def _runtime_on(_tenant_id: uuid.UUID, _db: object = None) -> bool:
        return True

    def _ner_unavailable() -> None:
        raise PseudonymisationUnavailableError("missing models")

    monkeypatch.setattr(FeatureFlagService, "assert_enabled", _feature_on)
    monkeypatch.setattr("app.ai.gate.is_ai_enabled", _runtime_on)
    monkeypatch.setattr(
        "app.ai.pseudonymise.assert_production_pseudonymisation_ready",
        _ner_unavailable,
    )

    with pytest.raises(AiPipelineError, match="privacy boundary"):
        await assert_ai_enabled(object(), uuid.uuid4())


async def test_premium_gate_blocks_non_premium(family_ctx: dict, redis_flush: None) -> None:
    """assert_ai_premium raises 402 when there is no active premium subscription."""
    db = family_ctx["db"]
    with pytest.raises(AiPremiumRequiredError) as exc:
        await assert_ai_premium(db, family_ctx["tenant_id"])
    assert exc.value.status_code == 402


async def test_premium_gate_passes_with_premium(family_ctx: dict, redis_flush: None) -> None:
    """A premium active subscription passes the premium gate (no raise)."""
    db = family_ctx["db"]
    await insert_premium_subscription(db, family_ctx["tenant_id"])
    await assert_ai_premium(db, family_ctx["tenant_id"])  # must not raise
