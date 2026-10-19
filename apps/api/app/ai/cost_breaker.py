"""Cost circuit breaker — PRE-FLIGHT estimate + charge before any AI call (Plan 026 Step 6).

Pre-flight: estimate the token cost, charge it to the counters, THEN decide whether to allow
the call — so a runaway is stopped BEFORE Vertex is hit (the anti-pattern this closes: "hard
ceiling 503-per-request without flipping the flag").

Three Redis counters (incrbyfloat + TTL, one pipeline):
  - ai_budget:{tenant}:{YYYY-MM}   monthly tenant spend (35-day TTL → auto-restore on the 1st).
  - ai_burn_rate:{tenant}          rolling 60s burn (TTL 60s).
  - ai_budget:GLOBAL:{YYYY-MM}     platform-wide monthly rollup (35-day TTL).

Breakers:
  - HARD CEILING (tenant monthly > cap) → auto-flip the tenant Redis flag OFF +
    AI_BUDGET_EXHAUSTED audit + (Plan 008) admin email. Auto-restores next month (the monthly
    key expires; a new month starts at 0 and the consent grant re-sets the flag).
  - BURN-RATE (60s burn > 3x baseline) → flip flag off (manual unblock — a spike is
    suspicious; do not auto-restore mid-month).
  - PLATFORM CAP (global monthly > platform cap) → engage the GLOBAL kill switch.

FAIL-CLOSED: a Redis error during the charge means we cannot account for spend → deny the
call (return False). Never let an un-metered call through.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import structlog
from redis.exceptions import RedisError

logger = structlog.get_logger(__name__)

# Rough Gemini Flash EU pricing proxy (EUR per 1k tokens). Real numbers are tuned in ops; the
# estimate only needs to be monotonic + conservative for the breaker to work.
_EUR_PER_1K_INPUT = 0.0003
_EUR_PER_1K_OUTPUT = 0.0009
_CHARS_PER_TOKEN = 4  # tiktoken-equivalent rough estimate (no tokenizer dependency at MVP)
_MONTH_TTL_SECONDS = 60 * 60 * 24 * 35
_BURN_WINDOW_SECONDS = 60


def estimate_tokens(payload: dict) -> int:
    """Rough input-token estimate from total string length (~4 chars/token)."""
    total_chars = _sum_chars(payload)
    return max(1, total_chars // _CHARS_PER_TOKEN)


def _sum_chars(value: object) -> int:
    if isinstance(value, str):
        return len(value)
    if isinstance(value, dict):
        return sum(_sum_chars(v) for v in value.values())
    if isinstance(value, list):
        return sum(_sum_chars(v) for v in value)
    return 0


def estimate_cost_eur(input_tokens: int, output_tokens: int) -> float:
    return (input_tokens / 1000 * _EUR_PER_1K_INPUT) + (output_tokens / 1000 * _EUR_PER_1K_OUTPUT)


def _month_key(tenant_id: UUID, now: datetime) -> str:
    return f"ai_budget:{tenant_id}:{now:%Y-%m}"


def _global_key(now: datetime) -> str:
    return f"ai_budget:GLOBAL:{now:%Y-%m}"


def _burn_key(tenant_id: UUID) -> str:
    return f"ai_burn_rate:{tenant_id}"


async def check_and_charge(
    db: object,
    *,
    tenant_id: UUID,
    estimated_input_tokens: int,
    estimated_output_tokens: int = 256,
) -> bool:
    """Pre-flight charge + breaker decision. Returns True to ALLOW the call, False to DENY.

    On DENY for the hard ceiling / burn-rate the tenant flag is flipped OFF; on the platform
    cap the global kill switch is engaged. FAIL-CLOSED on any Redis error.
    """
    from app.config.settings import settings
    from app.core.redis import get_redis

    cost = estimate_cost_eur(estimated_input_tokens, estimated_output_tokens)
    now = datetime.now(UTC)
    redis = get_redis()
    try:
        pipe = redis.pipeline()
        pipe.incrbyfloat(_month_key(tenant_id, now), cost)
        pipe.expire(_month_key(tenant_id, now), _MONTH_TTL_SECONDS)
        pipe.incrbyfloat(_burn_key(tenant_id), cost)
        pipe.expire(_burn_key(tenant_id), _BURN_WINDOW_SECONDS)
        pipe.incrbyfloat(_global_key(now), cost)
        pipe.expire(_global_key(now), _MONTH_TTL_SECONDS)
        results = await pipe.execute()
    except (RedisError, OSError):
        logger.warning("ai_cost_charge_failed_fail_closed", tenant_id=str(tenant_id))
        return False
    finally:
        await redis.aclose()

    month_total = float(results[0])
    burn_rate = float(results[2])
    global_total = float(results[4])

    # Soft ceiling (80%) — log only (Sentry alert in prod via the warning level).
    if month_total > settings.ai_tenant_monthly_budget_eur * 0.8:
        logger.warning(
            "ai_budget_soft_ceiling", tenant_id=str(tenant_id), month_total_eur=month_total
        )

    # HARD CEILING — auto-flip flag off, audit, auto-restore next month.
    if month_total > settings.ai_tenant_monthly_budget_eur:
        await _flip_tenant_flag_off(
            db, tenant_id, reason="ai.budget.exhausted", month_total=month_total
        )
        return False

    # BURN-RATE breaker — 3x the rolling baseline (manual unblock).
    if burn_rate > 3 * settings.ai_burn_rate_baseline_eur:
        await _flip_tenant_flag_off(
            db, tenant_id, reason="ai.burn_rate.exceeded", month_total=month_total
        )
        return False

    # PLATFORM CAP — engage the global kill switch.
    if global_total > settings.ai_platform_monthly_budget_eur:
        from app.ai.gate import engage_global_kill

        await engage_global_kill(reason="platform_budget_exhausted", db=db)  # type: ignore[arg-type]
        return False

    return True


async def _flip_tenant_flag_off(
    db: object, tenant_id: UUID, *, reason: str, month_total: float
) -> None:
    """Flush the tenant Redis flag + emit AI_BUDGET_EXHAUSTED audit (Plan 016).

    The audit payload carries the reason + the breached total ONLY — never any insight
    content, profile name, or raw payload (no-PII observability invariant).
    """
    from sqlalchemy.ext.asyncio import AsyncSession

    from app.ai.gate import set_tenant_ai_flag
    from app.audit.event_kinds import AuditEventKind
    from app.audit.repository import AuditEventRepository
    from app.audit.schemas import NewAuditEvent

    await set_tenant_ai_flag(tenant_id, enabled=False)

    session: AsyncSession = db  # type: ignore[assignment]
    await AuditEventRepository(session).append(
        NewAuditEvent(
            event_kind=AuditEventKind.AI_BUDGET_EXHAUSTED,
            tenant_id=tenant_id,
            meta={"reason": reason, "month_total_eur": round(month_total, 6)},
        )
    )
    logger.critical("ai_budget_exhausted", tenant_id=str(tenant_id), reason=reason)
