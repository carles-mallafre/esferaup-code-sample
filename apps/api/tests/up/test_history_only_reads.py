"""Aggregates, Home, memory groups and attach-arxiu stop at a history-only reader's
cutoff under any DB role."""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.schemas.up import UPCreateRequest
from app.services.up_service import UPService
from tests.up.conftest import auth_headers, mint_access_token


async def _seed(up_ctx, second_user, *, occurred_at: datetime | None = None):
    """One casa UP captured before the cutoff and two escola UPs captured after it,
    all occurring at the same moment, plus a history-only inherited reader."""
    from app.models.feed import FeedEntry
    from app.models.up import UP
    from tests.factories.profile import FamilyMembershipFactory

    db = up_ctx["db"]
    cutoff = datetime.now(UTC) - timedelta(days=1)
    captured = cutoff - timedelta(hours=1)
    occurred = occurred_at or captured
    old = UP(
        id=uuid.uuid4(),
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        author_user_id=up_ctx["admin_id"],
        category="casa",
        note_plain="OLDNOTE",
        occurred_at=occurred,
        created_at=captured,
        updated_at=captured,
    )
    db.add(old)
    db.add(
        FeedEntry(
            id=uuid.uuid4(),
            tenant_id=up_ctx["tenant_id"],
            profile_id=up_ctx["profile_id"],
            occurred_at=occurred,
            created_at=captured,
            entity_type="up",
            entity_id=old.id,
            category="casa",
            preview_plain="OLDNOTE",
            preview_search_tokens=[],
        )
    )
    await db.flush()
    new = [
        await UPService(db).create_up(
            up_ctx["tenant_id"],
            up_ctx["profile_id"],
            up_ctx["admin_id"],
            UPCreateRequest(
                category="escola", occurred_at=occurred + timedelta(minutes=minute), note="NEWNOTE"
            ),
        )
        for minute in (1, 2)
    ]
    await FamilyMembershipFactory(
        db,
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        user_id=second_user.id,
        role="view_only",
        authority_origin="inherited_handoff",
    )
    await db.execute(
        text(
            "INSERT INTO profile_temporal_access "
            "(id, tenant_id, profile_id, user_id, access_state, history_cutoff_at, "
            "future_access_enabled, header_snapshot_encrypted) "
            "VALUES (:id,:tid,:pid,:uid,'history_only',:cutoff,false,decode('00','hex'))"
        ),
        {
            "id": uuid.uuid4(),
            "tid": up_ctx["tenant_id"],
            "pid": up_ctx["profile_id"],
            "uid": second_user.id,
            "cutoff": cutoff,
        },
    )
    reader = auth_headers(await mint_access_token(second_user.id, up_ctx["tenant_id"], db))
    owner = auth_headers(await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db))
    return old, new, reader, owner, occurred


def _assert_hides_new(response, new) -> None:
    assert response.status_code == 200, response.text
    for up in new:
        assert str(up.id) not in response.text
    assert "NEWNOTE" not in response.text


async def test_history_only_esferes_count_only_retained_ups(test_client, up_ctx, second_user):
    _old, new, reader, owner, _ = await _seed(up_ctx, second_user)
    base = f"/api/v1/profiles/{up_ctx['profile_id']}/esferes"
    for suffix in ("", "?range=30d"):
        radar = await test_client.get(base + suffix, headers=reader)
        assert radar.status_code == 200, radar.text
        counts = {item["category"]: item["count"] for item in radar.json()["esferes"]}
        assert counts["casa"] == 1
        assert counts["escola"] == 0
        detail = await test_client.get(f"{base}/escola{suffix}", headers=reader)
        _assert_hides_new(detail, new)
        assert detail.json()["count"] == 0
        assert detail.json()["recent_items"] == []
        assert sum(point["count"] for point in detail.json()["timeline"]) == 0
    radar = await test_client.get(base, headers=reader)
    seen = datetime.fromisoformat(radar.json()["last_updated_at"])
    assert seen < datetime.now(UTC) - timedelta(days=1)

    full = await test_client.get(base, headers=owner)
    assert {i["category"]: i["count"] for i in full.json()["esferes"]}["escola"] == 2


async def test_history_only_period_summary_counts_only_retained_ups(
    test_client, up_ctx, second_user
):
    old, new, reader, owner, occurred = await _seed(up_ctx, second_user)
    url = (
        f"/api/v1/profiles/{up_ctx['profile_id']}/historic/summary"
        f"?period=month&reference={occurred.date().isoformat()}"
    )
    summary = await test_client.get(url, headers=reader)
    _assert_hides_new(summary, new)
    assert summary.json()["stats"]["total_ups"] == 1
    assert summary.json()["stats"]["categories"] == {"casa": 1}
    assert [h["item"]["entity_id"] for h in summary.json()["highlights"]] == [str(old.id)]

    full = await test_client.get(url, headers=owner)
    assert full.json()["stats"]["total_ups"] == 3


async def test_history_only_home_is_not_served_the_full_readers_payload(
    test_client, up_ctx, second_user, redis_flush
):
    old, new, reader, owner, _ = await _seed(up_ctx, second_user, occurred_at=datetime.now(UTC))
    url = f"/api/v1/home/{up_ctx['profile_id']}"
    full = await test_client.get(url, headers=owner)
    assert full.json()["last_up"]["entity_id"] == str(new[1].id)
    assert full.json()["evolucio"]["category"] == "escola"

    home = await test_client.get(url, headers=reader)
    _assert_hides_new(home, new)
    assert home.json()["last_up"]["entity_id"] == str(old.id)
    assert home.json()["evolucio"]["category"] == "casa"

    again = await test_client.get(url, headers=owner)
    assert again.json()["last_up"]["entity_id"] == str(new[1].id)


async def test_history_only_memory_groups_hold_only_retained_ups(
    test_client, up_ctx, second_user, monkeypatch
):
    from app.services.memory_group_service import MemoryGroupService

    async def _no_serving_record(*_args) -> None:
        """The serving record opens its own session, outside this test's transaction."""

    monkeypatch.setattr(MemoryGroupService, "record_serving", staticmethod(_no_serving_record))
    today = datetime.now(UTC).date()
    month = today.month - 6
    anchor = today.replace(year=today.year + (month - 1) // 12, month=(month - 1) % 12 + 1, day=1)
    occurred = datetime(anchor.year, anchor.month, 10, 12, tzinfo=UTC)
    old, new, reader, owner, _ = await _seed(up_ctx, second_user, occurred_at=occurred)
    base = f"/api/v1/profiles/{up_ctx['profile_id']}/memories/groups"
    key = f"month_anniversary:{anchor.isoformat()}"

    full = await test_client.get(base, headers=owner)
    assert {g["key"]: g["up_count"] for g in full.json()["groups"]}[key] == 3

    groups = await test_client.get(base, headers=reader)
    _assert_hides_new(groups, new)
    group = next(g for g in groups.json()["groups"] if g["key"] == key)
    assert group["up_count"] == 1
    assert group["cover_up_id"] == str(old.id)

    members = await test_client.get(f"{base}/{key}", headers=reader)
    _assert_hides_new(members, new)
    assert [item["entity_id"] for item in members.json()["data"]] == [str(old.id)]


async def test_history_only_attach_arxiu_treats_a_hidden_up_as_missing(
    test_client, up_ctx, second_user
):
    _old, new, reader, _owner, _ = await _seed(up_ctx, second_user)
    body = {"attachment_index": 0, "section": "escola"}

    async def attach(up_id):
        return await test_client.post(
            f"/api/v1/ups/{up_id}/attach-arxiu",
            headers={**reader, "Idempotency-Key": str(uuid.uuid4())},
            json=body,
        )

    missing = await attach(uuid.uuid4())
    assert missing.status_code == 404, missing.text
    hidden = await attach(new[0].id)
    assert hidden.status_code == missing.status_code, hidden.text
    assert hidden.json()["error"]["code"] == missing.json()["error"]["code"]
