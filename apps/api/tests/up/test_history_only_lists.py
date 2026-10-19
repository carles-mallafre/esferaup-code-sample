"""A history-only reader's UP lists and restore stop at the cutoff under any DB role."""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.schemas.up import UPCreateRequest
from app.services.up_service import UPService
from tests.up.conftest import auth_headers, mint_access_token


async def test_history_only_lists_stop_at_the_cutoff_and_restore_is_hidden(
    test_client, up_ctx, second_user
):
    from app.models.feed import FeedEntry
    from app.models.up import UP
    from tests.factories.profile import FamilyMembershipFactory

    db = up_ctx["db"]

    cutoff = datetime.now(UTC) - timedelta(days=1)
    at = cutoff - timedelta(hours=1)
    old = UP(
        id=uuid.uuid4(),
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        author_user_id=up_ctx["admin_id"],
        category="casa",
        note_plain="OLDNOTE",
        occurred_at=at,
        created_at=at,
        updated_at=at,
    )
    db.add(old)
    db.add(
        FeedEntry(
            id=uuid.uuid4(),
            tenant_id=up_ctx["tenant_id"],
            profile_id=up_ctx["profile_id"],
            occurred_at=at,
            created_at=at,
            entity_type="up",
            entity_id=old.id,
            category="casa",
            preview_plain="OLDNOTE",
            preview_search_tokens=[],
        )
    )
    await db.flush()
    new = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="escola", occurred_at=datetime.now(UTC), note="NEWNOTE"),
    )
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
    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], db)
    headers = auth_headers(token)
    pid = up_ctx["profile_id"]
    today = datetime.now(UTC).date().isoformat()
    for path in (
        f"/api/v1/profiles/{pid}/ups",
        f"/api/v1/profiles/{pid}/feed",
        f"/api/v1/profiles/{pid}/ups?query=NOTE",
        f"/api/v1/profiles/{pid}/historic/month?date={at.date().isoformat()}",
        f"/api/v1/profiles/{pid}/historic/month?date={today}",
        f"/api/v1/profiles/{pid}/historic/year?date={today}",
    ):
        response = await test_client.get(path, headers=headers)
        assert response.status_code == 200, response.text
        assert str(new.id) not in response.text, path
        assert "NEWNOTE" not in response.text, path
        assert "escola" not in response.text, path
    listed = await test_client.get(f"/api/v1/profiles/{pid}/ups", headers=headers)
    assert [item["entity_id"] for item in listed.json()["data"]] == [str(old.id)]

    owner_token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    owner = await test_client.get(f"/api/v1/profiles/{pid}/ups", headers=auth_headers(owner_token))
    assert {item["entity_id"] for item in owner.json()["data"]} == {str(old.id), str(new.id)}

    await UPService(db).delete_up(up_ctx["tenant_id"], new.id, up_ctx["admin_id"])
    restore = await test_client.post(
        f"/api/v1/ups/{new.id}/restore",
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
    )
    assert restore.status_code == 404, restore.text
    assert restore.json()["error"]["code"] == "UP_NOT_FOUND"
