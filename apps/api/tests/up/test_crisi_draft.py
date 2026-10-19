"""'Acabar més tard': a Crisi draft can be saved without a trigger and completed later."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import text

from app.schemas.up import CrisiData, CrisiPatchData, UPCreateRequest, UPPatchRequest
from app.services.up_service import UPService
from app.up.errors import NotACrisiError, TriggerRequiredError

pytestmark = pytest.mark.integration


async def _create_draft(up_ctx) -> str:
    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(
            category="emocions",
            occurred_at=datetime.now(UTC),
            is_crisi=True,
            crisi=CrisiData(duration_bucket="five_to_15", draft=True),
        ),
    )
    await up_ctx["db"].flush()
    return str(result.id)


async def _flags(db, up_id: str) -> tuple[bool, bool]:
    row = (
        await db.execute(
            text(
                "SELECT c.draft, fe.crisi_draft FROM up_crisi c "
                "JOIN feed_entries fe ON fe.entity_type = 'up' AND fe.entity_id = c.up_id "
                "WHERE c.up_id = :id"
            ),
            {"id": up_id},
        )
    ).one()
    return bool(row[0]), bool(row[1])


@pytest.mark.asyncio
async def test_draft_without_trigger_is_flagged_on_the_feed(up_ctx):
    up_id = await _create_draft(up_ctx)

    assert await _flags(up_ctx["db"], up_id) == (True, True)
    detail = await UPService(up_ctx["db"]).get_up_decrypted(
        up_ctx["tenant_id"], up_id, user_id=up_ctx["admin_id"]
    )
    assert detail["crisi"]["draft"] is True
    assert detail["crisi"]["trigger_text"] is None
    assert detail["crisi"]["duration_bucket"] == "five_to_15"


@pytest.mark.asyncio
async def test_completing_a_draft_clears_the_flag_and_keeps_the_texts(up_ctx):
    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)

    detail = await UPService(db).patch_up(
        up_ctx["tenant_id"],
        up_id,
        up_ctx["admin_id"],
        UPPatchRequest(
            crisi=CrisiPatchData(
                trigger_text="massa soroll al supermercat",
                resolution_text="hem sortit i ha passat",
                mood_after="happy",
                draft=False,
            )
        ),
    )

    assert detail["crisi"]["draft"] is False
    assert detail["crisi"]["trigger_text"] == "massa soroll al supermercat"
    assert detail["crisi"]["resolution_text"] == "hem sortit i ha passat"
    assert detail["crisi"]["duration_bucket"] == "five_to_15"
    assert await _flags(db, up_id) == (False, False)
    stored = (
        await db.execute(
            text("SELECT trigger_text, search_tokens FROM up_crisi WHERE up_id = :id"),
            {"id": up_id},
        )
    ).one()
    assert b"massa soroll" not in bytes(stored[0])
    assert len(stored[1]) > 0
    meta = (
        await db.execute(
            text(
                "SELECT payload FROM audit_events WHERE entity_id = :id "
                "AND event_type = 'up.updated' ORDER BY occurred_at DESC LIMIT 1"
            ),
            {"id": up_id},
        )
    ).scalar_one()
    assert meta["crisi_completed"] is True


@pytest.mark.asyncio
async def test_completing_still_requires_a_trigger(up_ctx):
    up_id = await _create_draft(up_ctx)

    with pytest.raises(TriggerRequiredError):
        await UPService(up_ctx["db"]).patch_up(
            up_ctx["tenant_id"],
            up_id,
            up_ctx["admin_id"],
            UPPatchRequest(crisi=CrisiPatchData(draft=False)),
        )


@pytest.mark.asyncio
async def test_a_draft_deleted_by_the_other_adult_is_no_longer_available(up_ctx):
    from app.up.errors import UPNotFoundError
    from tests.factories.profile import FamilyMembershipFactory
    from tests.factories.user import UserFactory

    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)
    other = await UserFactory(db, tenant_id=up_ctx["tenant_id"], is_verified=True)
    await FamilyMembershipFactory(
        db, up_ctx["tenant_id"], up_ctx["profile_id"], other.id, role="edit"
    )
    await db.flush()

    await UPService(db).delete_up(up_ctx["tenant_id"], up_id, other.id)

    with pytest.raises(UPNotFoundError):
        await UPService(db).get_up_decrypted(up_ctx["tenant_id"], up_id, user_id=up_ctx["admin_id"])
    with pytest.raises(UPNotFoundError):
        await UPService(db).patch_up(
            up_ctx["tenant_id"],
            up_id,
            up_ctx["admin_id"],
            UPPatchRequest(crisi=CrisiPatchData(trigger_text="tard", draft=False)),
        )


@pytest.mark.asyncio
async def test_crisi_patch_on_a_plain_up_is_refused(up_ctx):
    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at=datetime.now(UTC), note="torre"),
    )
    await up_ctx["db"].flush()

    with pytest.raises(NotACrisiError):
        await UPService(up_ctx["db"]).patch_up(
            up_ctx["tenant_id"],
            result.id,
            up_ctx["admin_id"],
            UPPatchRequest(crisi=CrisiPatchData(trigger_text="x", draft=False)),
        )


async def _moments(db, up_id: str) -> tuple[datetime, datetime]:
    row = (
        await db.execute(
            text(
                "SELECT u.occurred_at, fe.occurred_at FROM ups u "
                "JOIN feed_entries fe ON fe.entity_type = 'up' AND fe.entity_id = u.id "
                "WHERE u.id = :id"
            ),
            {"id": up_id},
        )
    ).one()
    return row[0], row[1]


@pytest.mark.asyncio
async def test_completing_a_draft_keeps_the_moment_changed_on_resume(up_ctx):
    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)
    moment = datetime(2026, 10, 14, 18, 30, tzinfo=UTC)

    detail = await UPService(db).patch_up(
        up_ctx["tenant_id"],
        up_id,
        up_ctx["admin_id"],
        UPPatchRequest(
            crisi=CrisiPatchData(occurred_at=moment, trigger_text="soroll", draft=False)
        ),
    )

    assert detail["occurred_at"] == moment
    assert await _moments(db, up_id) == (moment, moment)


@pytest.mark.asyncio
async def test_finish_later_also_keeps_a_changed_moment(up_ctx):
    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)
    moment = datetime(2026, 10, 13, 9, 0, tzinfo=UTC)

    await UPService(db).patch_up(
        up_ctx["tenant_id"],
        up_id,
        up_ctx["admin_id"],
        UPPatchRequest(crisi=CrisiPatchData(occurred_at=moment, draft=True)),
    )

    assert await _moments(db, up_id) == (moment, moment)


@pytest.mark.asyncio
async def test_a_completed_crisis_keeps_its_moment(up_ctx):
    from app.errors import AppError

    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)
    await UPService(db).patch_up(
        up_ctx["tenant_id"],
        up_id,
        up_ctx["admin_id"],
        UPPatchRequest(crisi=CrisiPatchData(trigger_text="soroll", draft=False)),
    )
    stored, _ = await _moments(db, up_id)

    unchanged = await UPService(db).patch_up(
        up_ctx["tenant_id"],
        up_id,
        up_ctx["admin_id"],
        UPPatchRequest(crisi=CrisiPatchData(occurred_at=stored, resolution_text="ja està")),
    )
    assert unchanged["crisi"]["resolution_text"] == "ja està"
    with pytest.raises(AppError) as exc_info:
        await UPService(db).patch_up(
            up_ctx["tenant_id"],
            up_id,
            up_ctx["admin_id"],
            UPPatchRequest(crisi=CrisiPatchData(occurred_at=datetime(2026, 1, 1, tzinfo=UTC))),
        )
    assert exc_info.value.code == "CRISI_MOMENT_FIXED"
    assert await _moments(db, up_id) == (stored, stored)


@pytest.mark.asyncio
async def test_resuming_over_http_saves_the_changed_moment(up_ctx, test_client):
    import uuid

    from tests.up.conftest import auth_headers, mint_access_token

    db = up_ctx["db"]
    up_id = await _create_draft(up_ctx)
    await db.commit()
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)

    response = await test_client.patch(
        f"/api/v1/ups/{up_id}",
        headers={**auth_headers(token), "Idempotency-Key": str(uuid.uuid4())},
        json={
            "crisi": {
                "occurred_at": "2026-10-14T16:30:00Z",
                "trigger_text": "massa soroll",
                "draft": False,
            }
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["occurred_at"].startswith("2026-10-14T16:30:00")
    assert response.json()["crisi"]["draft"] is False
