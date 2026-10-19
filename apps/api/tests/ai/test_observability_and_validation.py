"""Plan 026 Steps 5, 10 — no-PII observability + retry-once validation failure.

ai.insight.computed must carry HASHES + metadata ONLY — never prompt content, raw response,
UP text, profile name, or tenant_id. A model whose output fails validation twice → null +
AI_INSIGHT_VALIDATION_FAILED.
"""

from __future__ import annotations

import pytest
import structlog
from sqlalchemy import text

from app.ai.client import _set_ai_client_for_testing
from app.ai.insight_service import InsightService
from tests.factories.up import UPFactory

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _relax_k_anon(monkeypatch):
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 1)


async def _seed_ups(family_ctx: dict, n: int = 2) -> None:
    db = family_ctx["db"]
    for _ in range(n):
        await UPFactory(
            db,
            tenant_id=family_ctx["tenant_id"],
            profile_id=family_ctx["profile_id"],
            author_user_id=family_ctx["admin_id"],
            category="casa",
        )
    await db.flush()


async def test_no_pii_in_computed_log(family_ctx: dict, ai_client_stub, redis_flush: None) -> None:
    """ai.insight.computed contains NO content / profile name / tenant_id — hashes only."""
    db = family_ctx["db"]
    await _seed_ups(family_ctx)

    # capture_logs() captures regardless of the (already-bound) module logger config — robust
    # across the shared test session (unlike a global structlog.configure swap).
    with structlog.testing.capture_logs() as captured:
        result = await InsightService(db).compute(
            family_ctx["tenant_id"],
            family_ctx["profile_id"],
            prompt_id="insight_family_weekly",
            prompt_version="v1",
        )

    assert result is not None
    computed = [e for e in captured if e.get("event") == "ai.insight.computed"]
    assert computed, "ai.insight.computed not logged"
    entry = computed[0]
    blob = repr(entry)
    # No tenant_id key.
    assert "tenant_id" not in entry
    # No raw tenant/profile UUID (only one-way hashes).
    assert str(family_ctx["tenant_id"]) not in blob
    assert str(family_ctx["profile_id"]) not in blob
    # No insight body content.
    assert result["body_ca"] not in blob
    assert "Marc" not in blob  # the profile display name
    # Hash prefixes ARE present.
    assert "sha256_payload_prefix" in entry
    assert "profile_id_hash" in entry


async def test_validation_failure_returns_null_and_audits(
    family_ctx: dict, redis_flush: None
) -> None:
    """A client whose output fails the schema twice → null + AI_INSIGHT_VALIDATION_FAILED."""
    await _seed_ups(family_ctx)
    db = family_ctx["db"]

    class _BadClient:
        async def generate_insight(self, **kwargs):
            # Missing required fields → InsightResponse validation fails both attempts.
            return {"kind": "plan_recommendation"}

    _set_ai_client_for_testing(_BadClient())
    try:
        result = await InsightService(db).compute(
            family_ctx["tenant_id"],
            family_ctx["profile_id"],
            prompt_id="insight_family_weekly",
            prompt_version="v1",
        )
    finally:
        _set_ai_client_for_testing(None)

    assert result is None
    count = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.insight.validation_failed'"
            ),
            {"tid": str(family_ctx["tenant_id"])},
        )
    ).scalar_one()
    assert count >= 1


async def test_voice_lock_failure_returns_null(family_ctx: dict, redis_flush: None) -> None:
    """A client returning a FORBIDDEN-phrase output (valid schema) → null (voice-lock guard)."""
    await _seed_ups(family_ctx)
    db = family_ctx["db"]

    class _ForbiddenClient:
        async def generate_insight(self, **kwargs):
            return {
                "kind": "plan_recommendation",
                "title_ca": "Diagnòstic",
                "title_es": "Diagnóstico",
                "body_ca": "Aquest és un diagnòstic de TEA.",
                "body_es": "Esto es un diagnóstico de TEA.",
                "source_up_ids": [],
                "confidence_band": "low",
                "disclaimer_required": True,
            }

    _set_ai_client_for_testing(_ForbiddenClient())
    try:
        result = await InsightService(db).compute(
            family_ctx["tenant_id"],
            family_ctx["profile_id"],
            prompt_id="insight_family_weekly",
            prompt_version="v1",
        )
    finally:
        _set_ai_client_for_testing(None)
    assert result is None  # forbidden phrase → rejected
