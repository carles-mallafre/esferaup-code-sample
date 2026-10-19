"""The global AI kill switch holds until someone releases it, and both acts are recorded."""

from __future__ import annotations

import uuid
from unittest.mock import patch

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai import gate
from app.core.redis import get_redis
from app.services.ai_governance_service import AiGovernanceService
from tests.ai.conftest import grant_platform_staff
from tests.family.conftest import auth_headers, mint_access_token

pytestmark = pytest.mark.asyncio

ENGAGE = "/api/v1/internal/ai/kill-switch"
RELEASE = "/api/v1/internal/ai/kill-switch/release"
HEALTH = "/api/v1/internal/ai/model-health"


async def _staff_headers(family_ctx: dict, db: AsyncSession) -> dict[str, str]:
    await grant_platform_staff(db, family_ctx["admin_id"])
    token = await mint_access_token(family_ctx["admin_id"], family_ctx["tenant_id"], db)
    return auth_headers(token)


async def _post(client: AsyncClient, url: str, headers: dict, reason: str):
    return await client.post(
        url, headers={**headers, "Idempotency-Key": str(uuid.uuid4())}, json={"reason": reason}
    )


async def _drop_redis_key() -> None:
    redis = get_redis()
    try:
        await redis.delete("ai:kill_global")
    finally:
        await redis.aclose()


async def test_engaged_switch_has_no_expiry(redis_flush: None) -> None:
    await gate.engage_global_kill(reason="test")

    redis = get_redis()
    try:
        assert await redis.ttl("ai:kill_global") == -1
    finally:
        await redis.aclose()
    assert await gate.is_global_kill_active() is True


async def test_switch_survives_losing_the_redis_key(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    assert (await _post(test_client, ENGAGE, headers, "incident 12")).status_code == 200

    await _drop_redis_key()

    assert await gate.is_global_kill_active(db) is True
    assert await gate.is_ai_enabled(family_ctx["tenant_id"], db) is False
    health = (await test_client.get(HEALTH, headers=headers)).json()
    assert health["kill_global"] is True
    assert health["kill_switch"]["source"] == "admin"


async def test_unreadable_durable_state_counts_as_engaged(redis_flush: None) -> None:
    async def _boom(_db):
        raise OperationalError("SELECT", {}, Exception("database down"))

    with patch("app.ai.gate._durable_kill_engaged", _boom):
        assert await gate.is_global_kill_active() is True
        assert await gate.is_ai_enabled(uuid.uuid4()) is False


async def test_engage_and_release_are_recorded_and_shown(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)

    idle = (await test_client.get(HEALTH, headers=headers)).json()["kill_switch"]
    assert idle == {
        "engaged": False,
        "source": None,
        "releasable": False,
        "changed_at": None,
        "changed_by": None,
        "changed_by_user_id": None,
        "reason": None,
    }

    assert (await _post(test_client, ENGAGE, headers, "incident 12")).status_code == 200
    engaged = (await test_client.get(HEALTH, headers=headers)).json()["kill_switch"]
    assert engaged["engaged"] is True
    assert engaged["releasable"] is True
    assert engaged["changed_by"] == "self"
    assert engaged["changed_by_user_id"] == str(family_ctx["admin_id"])
    assert engaged["reason"] == "incident 12"
    assert engaged["changed_at"] is not None

    released = await _post(test_client, RELEASE, headers, "incident 12 closed")
    assert released.status_code == 200, released.text
    assert released.json() == {"engaged": False}
    assert await gate.is_global_kill_active(db) is False
    after = (await test_client.get(HEALTH, headers=headers)).json()
    assert after["kill_global"] is False
    assert after["kill_switch"]["engaged"] is False
    assert after["kill_switch"]["changed_by"] == "self"
    assert after["kill_switch"]["reason"] == "incident 12 closed"

    events = (
        await db.execute(
            text(
                "SELECT event_type, user_id, payload->>'reason' FROM audit_events "
                "WHERE event_type LIKE 'internal_admin.ai_kill_switch.%' ORDER BY occurred_at, id"
            )
        )
    ).all()
    assert sorted(tuple(event) for event in events) == [
        ("internal_admin.ai_kill_switch.disengaged", family_ctx["admin_id"], "incident 12 closed"),
        ("internal_admin.ai_kill_switch.engaged", family_ctx["admin_id"], "incident 12"),
    ]


async def test_environment_switch_cannot_be_released(
    test_client: AsyncClient, family_ctx: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.config.settings import settings

    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    monkeypatch.setattr(settings, "kill_ai_global", True)

    state = (await test_client.get(HEALTH, headers=headers)).json()["kill_switch"]
    assert (state["engaged"], state["source"], state["releasable"]) == (True, "environment", False)

    refused = await _post(test_client, RELEASE, headers, "trying anyway")
    assert refused.status_code == 409
    assert refused.json()["error"]["code"] == "KILL_SWITCH_ENVIRONMENT_LOCKED"


async def test_system_engage_is_durable_and_attributed_to_no_one(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)

    await gate.engage_global_kill(reason="platform_budget_exhausted", db=db)
    await _drop_redis_key()

    state = (await test_client.get(HEALTH, headers=headers)).json()["kill_switch"]
    assert state["engaged"] is True
    assert (state["source"], state["changed_by"]) == ("system", "system")
    assert state["reason"] == "platform_budget_exhausted"
    assert state["releasable"] is True


async def test_coaches_and_authoring_follow_the_live_switch(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    author_id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO activa_authors (id, user_id, display_name, verified) "
            "VALUES (:id, :uid, 'Coach Test', true)"
        ),
        {"id": author_id, "uid": family_ctx["admin_id"]},
    )
    await db.flush()
    service = AiGovernanceService.from_session(db)
    assert (await service.resolve_for_author(author_id)).enabled is True

    assert (await _post(test_client, ENGAGE, headers, "incident 12")).status_code == 200

    assert (await service.resolve_for_author(author_id)).enabled is False
    coaches = await test_client.get("/api/v1/internal/admin/ai/coaches", headers=headers)
    assert coaches.status_code == 200, coaches.text
    items = coaches.json()["items"]
    assert items and all(item["enabled"] is False for item in items)

    assert (await _post(test_client, RELEASE, headers, "closed")).status_code == 200
    assert (await service.resolve_for_author(author_id)).enabled is True
