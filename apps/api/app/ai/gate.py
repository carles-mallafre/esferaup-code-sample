"""AI dual gate — FAIL-CLOSED flag resolution + the EU AI Act kill switch (Plan 026 Step 2).

is_ai_enabled(tenant_id) is the single entry-point every AI endpoint + the Celery beat call
BEFORE doing any work. It is FAIL-CLOSED by construction (the anti-pattern this closes is
"failing OPEN on Redis" — API.md §11.13):

  1. The GLOBAL kill switch is checked FIRST: the KILL_AI_GLOBAL boot flag, the Redis key
     ai:kill_global (no expiry) or the durable ai_global_config.kill_engaged row → if any is
     set, return False for EVERY tenant. An unreadable Redis or database counts as engaged.
  2. The per-tenant Redis flag ai:flag:{tenant_id} must be the exact string 'true'.
  3. ANY Redis error (ConnectionError/TimeoutError/RedisError) OR a missing key → False.

The DPIA gate (503 FEATURE_FLAG_DISABLED until compliance_attestations.dpia_ai_art22 is
signed) is enforced by two layers we REUSE, not re-implement:
  - The startup guard (app.auth.startup_guard.assert_dpia_attestation_valid) refuses to boot
    if feature_ai_enabled=True without the signed attestation.
  - The per-request FeatureFlagService.assert_enabled(tenant_id, 'ai') raises
    FeatureFlagDisabledError → 503 FEATURE_FLAG_DISABLED when the global/tenant flag is off.

At MVP the feature_ai_enabled global flag is False, so assert_ai_enabled ALWAYS raises 503
FEATURE_FLAG_DISABLED — the infrastructure ships DARK. is_ai_enabled additionally gates on
the Redis runtime flag so the cost circuit breaker can flip a single tenant off mid-month
without a redeploy.

Premium gate: AI is a paid-tier capability. assert_ai_premium uses the Plan 025
SubscriptionEntitlement reader (premium + active/trialing/in_grace_period) — a non-premium
tenant is blocked.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID

import structlog
from redis.exceptions import RedisError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.errors import AppError

if TYPE_CHECKING:
    from sqlalchemy.ext.asyncio import AsyncSession

logger = structlog.get_logger(__name__)

_AI_FEATURE_KEY = "ai"
_KILL_GLOBAL_KEY = "ai:kill_global"


def _flag_key(tenant_id: UUID) -> str:
    return f"ai:flag:{tenant_id}"


class AiPipelineError(AppError):
    """Flag is ON but the pipeline failed → 503 AI_PIPELINE_ERROR.

    Distinct from FEATURE_FLAG_DISABLED (flag off) and INSUFFICIENT_ANONYMITY_SET (k<5),
    per API.md §11.12 — three distinct 503 codes the GET insight endpoint surfaces.
    """

    def __init__(self, message: str = "AI insight pipeline temporarily unavailable.") -> None:
        super().__init__(code="AI_PIPELINE_ERROR", status_code=503, message=message)


class InsufficientAnonymitySetError(AppError):
    """K-anonymity cohort below threshold → 503 INSUFFICIENT_ANONYMITY_SET (Plan 026 Step 4)."""

    def __init__(self) -> None:
        super().__init__(
            code="INSUFFICIENT_ANONYMITY_SET",
            status_code=503,
            message=(
                "Not enough comparable data to generate a privacy-safe insight yet. "
                "A generic recommendation is shown instead."
            ),
        )


class AiPremiumRequiredError(AppError):
    """AI is a premium-tier capability → 402 (mirrors the Activa paywall)."""

    def __init__(self) -> None:
        super().__init__(
            code="SUBSCRIPTION_REQUIRED",
            status_code=402,
            message="AI insights require an active premium subscription.",
        )


async def _durable_kill_engaged(db: AsyncSession | None) -> bool:
    query = text("SELECT kill_engaged FROM ai_global_config WHERE id = 1")
    if db is not None:
        return bool((await db.execute(query)).scalar())

    from app.db.session import AsyncSessionLocal

    async with AsyncSessionLocal() as session:
        return bool((await session.execute(query)).scalar())


async def is_global_kill_active(db: AsyncSession | None = None) -> bool:
    """True if the EU AI Act kill switch is engaged. FAIL-CLOSED on any read error.

    Engaged when any of these says so: the KILL_AI_GLOBAL boot flag, the Redis key (set
    first on engage, so a stop is immediate on every worker) or the durable
    ai_global_config row, which survives a Redis flush or restart. An unreachable Redis or
    database is treated as 'killed' (deny), never 'allowed'. Pass the request session when
    there is one; otherwise the durable row is read on a short session of its own.
    """
    from app.config.settings import settings

    if settings.kill_ai_global:
        return True

    from app.core.redis import get_redis

    redis = get_redis()
    try:
        if await redis.get(_KILL_GLOBAL_KEY) is not None:
            return True
    except (RedisError, OSError):
        logger.warning("ai_kill_switch_check_failed_fail_closed", store="redis")
        return True
    finally:
        await redis.aclose()

    try:
        return await _durable_kill_engaged(db)
    except (SQLAlchemyError, OSError):
        logger.warning("ai_kill_switch_check_failed_fail_closed", store="database")
        return True


async def is_ai_enabled(tenant_id: UUID, db: AsyncSession | None = None) -> bool:
    """Return True ONLY if AI is enabled for this tenant — FAIL-CLOSED on any Redis error.

    Order (the kill switch is checked FIRST):
      1. Global kill switch engaged → False.
      2. Redis ai:flag:{tenant_id} == 'true' → True.
      3. Anything else (miss, wrong value, Redis error) → False.
    """
    if await is_global_kill_active(db):
        return False

    from app.core.redis import get_redis

    redis = get_redis()
    try:
        val = await redis.get(_flag_key(tenant_id))
        return val == "true"
    except (RedisError, OSError):
        # FAIL-CLOSED: never fail open on a cache error (the cardinal anti-pattern).
        logger.warning("ai_flag_check_failed_fail_closed", tenant_id=str(tenant_id))
        return False
    finally:
        await redis.aclose()


async def set_tenant_ai_flag(tenant_id: UUID, enabled: bool) -> None:
    """Set/clear the per-tenant runtime AI flag in Redis. Best-effort (caller handles failure).

    Used by the consent grant/revoke path + the cost circuit breaker auto-flip. A flush
    (enabled=False) is fail-safe by definition; a failure to SET enabled=True simply leaves
    AI off (fail-closed), which is the safe direction.
    """
    from app.core.redis import get_redis

    redis = get_redis()
    try:
        if enabled:
            await redis.set(_flag_key(tenant_id), "true")
        else:
            await redis.delete(_flag_key(tenant_id))
    finally:
        await redis.aclose()


_SET_KILL_STATE = text(
    "UPDATE ai_global_config SET kill_engaged = :engaged, kill_changed_at = now(), "
    "kill_changed_by_user_id = :actor, kill_reason = :reason WHERE id = 1"
)


async def engage_global_kill(
    reason: str, *, db: AsyncSession | None = None, actor_user_id: UUID | None = None
) -> None:
    """Engage the kill switch until someone disengages it.

    Redis first: every worker refuses AI from its next check, whatever happens to the
    caller's transaction. Then the durable row, in the caller's transaction, which is what
    keeps the switch engaged across a Redis flush and tells the Admin who, when and why.
    The cost breaker's platform-cap path calls this with no actor (a system engage).
    """
    from app.core.redis import get_redis

    redis = get_redis()
    try:
        await redis.set(_KILL_GLOBAL_KEY, "1")
    except (RedisError, OSError):
        # The gate fails closed while Redis is unreachable; the durable row must still be
        # written, or the switch would lapse when Redis comes back.
        if db is None:
            raise
        logger.warning("ai_global_kill_redis_write_failed")
    finally:
        await redis.aclose()
    logger.critical("ai_global_kill_engaged", reason=reason)
    if db is not None:
        await db.execute(
            _SET_KILL_STATE,
            {"engaged": True, "actor": actor_user_id, "reason": reason},
        )


async def disengage_global_kill(reason: str, *, db: AsyncSession, actor_user_id: UUID) -> None:
    """Release the kill switch: the durable row first, then the Redis key.

    A failure to clear Redis propagates, so the caller's transaction rolls back and the
    switch stays engaged everywhere. The KILL_AI_GLOBAL boot flag is not touched: it is
    environment configuration and keeps AI off until ops remove it.
    """
    from app.core.redis import get_redis

    await db.execute(
        _SET_KILL_STATE,
        {"engaged": False, "actor": actor_user_id, "reason": reason},
    )
    redis = get_redis()
    try:
        await redis.delete(_KILL_GLOBAL_KEY)
    finally:
        await redis.aclose()
    logger.critical("ai_global_kill_disengaged", reason=reason)


async def assert_ai_enabled(db: object, tenant_id: UUID) -> None:
    """Assert AI is usable for this tenant or raise the correct 503.

    Two-stage:
      1. DPIA/feature gate: FeatureFlagService.assert_enabled(tenant_id, 'ai') → 503
         FEATURE_FLAG_DISABLED while the DPIA is unsigned (the global flag is False at MVP).
      2. Runtime Redis gate: is_ai_enabled → 503 FEATURE_FLAG_DISABLED if the per-tenant
         runtime flag is off (consent revoked / budget exhausted / kill switch).
    """

    from app.gdpr.feature_flags import FeatureFlagService

    session: AsyncSession = db  # type: ignore[assignment]

    # Stage 1: DPIA-gated feature flag (the dark-launch gate).
    await FeatureFlagService(session).assert_enabled(tenant_id, _AI_FEATURE_KEY)

    # Stage 2: runtime fail-closed Redis gate (per-tenant kill / budget / consent flush).
    if not await is_ai_enabled(tenant_id, session):
        from app.gdpr.feature_flags import FeatureFlagDisabledError

        raise FeatureFlagDisabledError(feature_key=_AI_FEATURE_KEY)

    # A per-tenant DB flag can enable AI while the global environment flag remains false, so
    # the startup-only check is not sufficient. Re-check the real NER boundary immediately
    # before every production pipeline entry; the model loader is process-cached.
    from app.ai.pseudonymise import (
        PseudonymisationUnavailableError,
        assert_production_pseudonymisation_ready,
    )

    try:
        assert_production_pseudonymisation_ready()
    except PseudonymisationUnavailableError as exc:
        logger.error("ai_pseudonymisation_unavailable_fail_closed")
        raise AiPipelineError("AI privacy boundary temporarily unavailable.") from exc


async def assert_ai_premium(db: object, tenant_id: UUID) -> None:
    """Raise AiPremiumRequiredError (402) unless the tenant holds an active premium sub."""

    from app.billing.entitlement import SubscriptionEntitlementReader

    session: AsyncSession = db  # type: ignore[assignment]
    if not await SubscriptionEntitlementReader().is_active(session, tenant_id):
        raise AiPremiumRequiredError()
