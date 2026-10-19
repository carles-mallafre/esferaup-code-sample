"""Plan 026 Step 7, 11, 13 — the AI HTTP endpoints (DARK posture).

The cardinal endpoint test: GET insight returns 503 FEATURE_FLAG_DISABLED at MVP (the DPIA is
unsigned + the global feature flag is off). Plus consent revoke, dismiss, kill switch, rollback.
"""

from __future__ import annotations

import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from tests.ai.conftest import grant_platform_staff, insert_premium_subscription
from tests.family.conftest import auth_headers, mint_access_token

pytestmark = pytest.mark.asyncio


async def _headers(family_ctx: dict, db: AsyncSession) -> dict[str, str]:
    token = await mint_access_token(family_ctx["admin_id"], family_ctx["tenant_id"], db)
    return auth_headers(token)


async def _staff_headers(family_ctx: dict, db: AsyncSession) -> dict[str, str]:
    """Headers for an internal-admin caller (granted in platform_staff)."""
    await grant_platform_staff(db, family_ctx["admin_id"])
    return await _headers(family_ctx, db)


async def test_get_insight_503_feature_flag_disabled(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    """The dark posture: GET insight → 503 FEATURE_FLAG_DISABLED (DPIA unsigned at MVP)."""
    db = family_ctx["db"]
    # Even with premium, the DPIA gate blocks (the dark-launch invariant).
    await insert_premium_subscription(db, family_ctx["tenant_id"])
    headers = await _headers(family_ctx, db)

    resp = await test_client.get(
        f"/api/v1/profiles/{family_ctx['profile_id']}/insights/{uuid.uuid4()}",
        headers=headers,
    )
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "FEATURE_FLAG_DISABLED"


async def test_revoke_consent_endpoint(test_client: AsyncClient, family_ctx: dict) -> None:
    """DELETE /v1/profiles/{id}/ai-consent revokes (200) — works regardless of the DPIA flag."""
    db = family_ctx["db"]
    headers = await _headers(family_ctx, db)
    resp = await test_client.delete(
        f"/api/v1/profiles/{family_ctx['profile_id']}/ai-consent", headers=headers
    )
    assert resp.status_code == 200
    assert "revoked" in resp.json()


async def test_consent_status_follows_grant_and_revoke(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _headers(family_ctx, db)
    url = f"/api/v1/profiles/{family_ctx['profile_id']}/ai-consent"

    assert (await test_client.get(url, headers=headers)).json() == {"granted": False}
    granted = await test_client.post(url, headers={**headers, "Idempotency-Key": str(uuid.uuid4())})
    assert granted.status_code == 201
    assert (await test_client.get(url, headers=headers)).json() == {"granted": True}
    assert (await test_client.delete(url, headers=headers)).status_code == 200
    assert (await test_client.get(url, headers=headers)).json() == {"granted": False}


async def test_dismiss_unknown_insight_404(test_client: AsyncClient, family_ctx: dict) -> None:
    """Dismissing a non-existent insight → 404 (no oracle)."""
    db = family_ctx["db"]
    headers = await _headers(family_ctx, db)
    headers["Idempotency-Key"] = str(uuid.uuid4())
    resp = await test_client.post(
        f"/api/v1/profiles/{family_ctx['profile_id']}/insights/{uuid.uuid4()}/dismiss",
        headers=headers,
    )
    assert resp.status_code == 404


async def test_kill_switch_endpoint(test_client: AsyncClient, family_ctx: dict) -> None:
    """POST /v1/internal/ai/kill-switch engages the global kill (Redis mirror)."""
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    headers["Idempotency-Key"] = str(uuid.uuid4())
    resp = await test_client.post(
        "/api/v1/internal/ai/kill-switch",
        headers=headers,
        json={"reason": "incident drill"},
    )
    assert resp.status_code == 200
    assert resp.json()["engaged"] is True


async def test_prompt_rollback_endpoint(test_client: AsyncClient, family_ctx: dict) -> None:
    """POST /v1/internal/ai/prompts/{id}/rollback sets the active version + audits."""
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    headers["Idempotency-Key"] = str(uuid.uuid4())
    resp = await test_client.post(
        "/api/v1/internal/ai/prompts/insight_family_weekly/rollback",
        headers=headers,
        json={"version": "v1", "reason": "regression"},
    )
    assert resp.status_code == 200
    assert resp.json()["active_version"] == "v1"


async def test_model_health_endpoint(test_client: AsyncClient, family_ctx: dict) -> None:
    """GET /v1/internal/ai/model-health reports the dark posture (provider stub, flag off)."""
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    resp = await test_client.get("/api/v1/internal/ai/model-health", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["provider"] == "stub"
    assert body["feature_ai_enabled"] is False


async def test_engaged_kill_switch_is_audited_and_reported_everywhere(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    """The Redis mirror — not the boot flag — is what the Admin must show, and who engaged
    it and why belongs in the audit log."""
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)

    before = await test_client.get("/api/v1/internal/ai/model-health", headers=headers)
    assert before.json()["kill_global"] is False

    engaged = await test_client.post(
        "/api/v1/internal/ai/kill-switch",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={"reason": "incident drill 2026-10"},
    )
    assert engaged.status_code == 200, engaged.text

    health = await test_client.get("/api/v1/internal/ai/model-health", headers=headers)
    config = await test_client.get("/api/v1/internal/admin/ai/config", headers=headers)
    overview = await test_client.get("/api/v1/internal/admin/overview", headers=headers)
    assert health.json()["kill_global"] is True
    assert config.json()["kill_global"] is True
    assert overview.json()["ai_kill_global"] is True

    events = (
        await db.execute(
            text(
                "SELECT user_id, payload->>'reason' AS reason FROM audit_events "
                "WHERE event_type = 'internal_admin.ai_kill_switch.engaged'"
            )
        )
    ).all()
    assert [tuple(event) for event in events] == [
        (family_ctx["admin_id"], "incident drill 2026-10")
    ]


async def test_model_health_reports_the_configured_default_model(
    test_client: AsyncClient, family_ctx: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The model in use is the default chosen in the global config, not the boot variable."""
    from app.config.settings import settings

    chosen = "gemini-3.5-flash"
    assert chosen != settings.gemini_model_name
    monkeypatch.setattr(settings, "gemini_selectable_models", [chosen])
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)

    saved = await test_client.patch(
        "/api/v1/internal/admin/ai/config",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={"default_model": chosen},
    )
    assert saved.status_code == 200, saved.text

    health = await test_client.get("/api/v1/internal/ai/model-health", headers=headers)
    assert health.json()["model_name"] == chosen
    assert health.json()["environment_model_name"] == settings.gemini_model_name

    # A stored default that is no longer selectable falls back to the boot model.
    monkeypatch.setattr(settings, "gemini_selectable_models", [])
    health = await test_client.get("/api/v1/internal/ai/model-health", headers=headers)
    assert health.json()["model_name"] == settings.gemini_model_name
