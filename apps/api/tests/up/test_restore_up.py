"""Recovering a deleted UP for 7 days: GET /v1/ups/deleted + POST /v1/ups/{id}/restore.

Driven over HTTP so the same tests cover the production role
(TEST_REQUEST_DB_ROLE=app_role).
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import text

from tests.family.conftest import bind_request_identity
from tests.idempotency_keys import idempotency_key
from tests.up.conftest import auth_headers, mint_access_token

pytestmark = pytest.mark.integration


def _hdr(token: str) -> dict:
    return {**auth_headers(token), "Idempotency-Key": idempotency_key()}


async def _admin_token(ctx: dict, db) -> str:
    return await mint_access_token(ctx["admin_id"], ctx["tenant_id"], db)


async def _create(test_client, ctx: dict, token: str, **body) -> str:
    payload = {"category": "casa", "occurred_at": "2026-05-26T10:00:00Z", "note": "built a tower"}
    payload.update(body)
    resp = await test_client.post(
        f"/api/v1/profiles/{ctx['profile_id']}/ups", headers=_hdr(token), json=payload
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


async def _delete(test_client, token: str, up_id: str) -> None:
    resp = await test_client.delete(f"/api/v1/ups/{up_id}", headers=_hdr(token))
    assert resp.status_code == 204, resp.text


async def _list(test_client, ctx: dict, token: str):
    return await test_client.get(
        f"/api/v1/ups/deleted?profile_id={ctx['profile_id']}", headers=auth_headers(token)
    )


async def _rebind(db, ctx: dict) -> None:
    await db.execute(text("RESET ROLE"))
    await bind_request_identity(db, ctx["tenant_id"], ctx["admin_id"], role="admin")


async def _view_only_token(db, ctx: dict, second_user) -> str:
    from app.services.family_service import FamilyService

    svc = FamilyService(db)
    inv = await svc.invite_member(
        ctx["tenant_id"],
        ctx["profile_id"],
        ctx["admin_id"],
        email=second_user._test_email,
        role="view_only",
    )
    await bind_request_identity(db, ctx["tenant_id"], second_user.id)
    await svc.accept_invite(ctx["tenant_id"], second_user.id, token=inv["invite_token"])
    await db.flush()
    return await mint_access_token(second_user.id, ctx["tenant_id"], db)


@pytest.mark.parametrize("edited", [False, True])
async def test_delete_list_restore_round_trip(test_client, db_session, up_ctx, edited):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    expected_note = "built a tower"
    if edited:
        expected_note = "built a taller tower after lunch"
        changed = await test_client.patch(
            f"/api/v1/ups/{up_id}",
            headers=_hdr(token),
            json={"note": expected_note, "mood": "happy", "tag": "tower-qa"},
        )
        assert changed.status_code == 200, changed.text
        reopened = await test_client.get(f"/api/v1/ups/{up_id}", headers=auth_headers(token))
        assert reopened.status_code == 200, reopened.text
        assert reopened.json()["note"] == expected_note
        assert reopened.json()["mood"] == "happy"
        assert reopened.json()["tag"] == "tower-qa"
    await _rebind(db, up_ctx)
    points_before = (
        await db.execute(
            text("SELECT count(*) FROM points_ledger WHERE profile_id = :pid"),
            {"pid": str(up_ctx["profile_id"])},
        )
    ).scalar_one()

    empty = await _list(test_client, up_ctx, token)
    assert empty.status_code == 200, empty.text
    assert empty.json() == {"items": []}

    await _delete(test_client, token, up_id)
    assert (
        await test_client.get(f"/api/v1/ups/{up_id}", headers=auth_headers(token))
    ).status_code == 404

    listed = await _list(test_client, up_ctx, token)
    assert listed.status_code == 200, listed.text
    (item,) = listed.json()["items"]
    assert item["id"] == up_id
    assert item["category"] == "casa"
    assert item["preview"] == expected_note
    assert item["days_left"] == 7
    assert listed.headers["cache-control"] == "private, no-store"

    restored = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert restored.status_code == 200, restored.text
    assert restored.json() == {
        "id": up_id,
        "profile_id": str(up_ctx["profile_id"]),
        "was_already": False,
    }

    got = await test_client.get(f"/api/v1/ups/{up_id}", headers=auth_headers(token))
    assert got.status_code == 200, got.text
    assert got.json()["note"] == expected_note
    if edited:
        assert got.json()["mood"] == "happy"
        assert got.json()["tag"] == "tower-qa"
    assert (await _list(test_client, up_ctx, token)).json() == {"items": []}

    again = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert again.status_code == 200
    assert again.json()["was_already"] is True

    await _rebind(db, up_ctx)
    feed_deleted_at = (
        await db.execute(
            text(
                "SELECT deleted_at FROM feed_entries WHERE entity_type = 'up' AND entity_id = :id"
            ),
            {"id": up_id},
        )
    ).scalar_one()
    assert feed_deleted_at is None
    audits = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'up.restored' AND entity_id = :id AND user_id = :uid"
            ),
            {"tid": str(up_ctx["tenant_id"]), "id": up_id, "uid": str(up_ctx["admin_id"])},
        )
    ).scalar_one()
    assert audits == 1
    outbox = (
        await db.execute(
            text(
                "SELECT count(*) FROM outbox_events "
                "WHERE event_type = 'up.restored' AND payload->>'up_id' = :id"
            ),
            {"id": up_id},
        )
    ).scalar_one()
    assert outbox == 1
    # The delete kept the points, so the restore must not award them again.
    points_after = (
        await db.execute(
            text("SELECT count(*) FROM points_ledger WHERE profile_id = :pid"),
            {"pid": str(up_ctx["profile_id"])},
        )
    ).scalar_one()
    assert points_after == points_before


async def test_restore_replays_on_same_idempotency_key(test_client, db_session, up_ctx):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    headers = _hdr(token)
    first = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=headers)
    second = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=headers)
    assert first.status_code == second.status_code == 200
    assert second.json() == first.json()
    assert first.json()["was_already"] is False

    await _rebind(db, up_ctx)
    audits = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up.restored' AND entity_id = :id"
            ),
            {"id": up_id},
        )
    ).scalar_one()
    assert audits == 1


async def test_restore_requires_idempotency_key_and_auth(test_client, db_session, up_ctx):
    token = await _admin_token(up_ctx, db_session)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    no_key = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=auth_headers(token))
    assert no_key.status_code in (400, 422), no_key.text
    no_auth = await test_client.post(
        f"/api/v1/ups/{up_id}/restore", headers={"Idempotency-Key": idempotency_key()}
    )
    assert no_auth.status_code == 401
    assert (
        await test_client.get(f"/api/v1/ups/deleted?profile_id={up_ctx['profile_id']}")
    ).status_code == 401


async def test_crisi_sidecar_comes_back_with_the_up(test_client, db_session, up_ctx):
    db = db_session
    token = await _admin_token(up_ctx, db)
    created = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/crisis",
        headers=_hdr(token),
        json={
            "occurred_at": "2026-05-26T10:00:00Z",
            "trigger_text": "loud noise at the market",
            "resolution_text": "a quiet corner",
        },
    )
    assert created.status_code == 201, created.text
    up_id = created.json()["up_id"]
    await _delete(test_client, token, up_id)

    listed = await _list(test_client, up_ctx, token)
    assert listed.status_code == 200, listed.text
    (item,) = listed.json()["items"]
    assert item["is_crisi"] is True

    restored = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert restored.status_code == 200, restored.text
    got = await test_client.get(f"/api/v1/ups/{up_id}", headers=auth_headers(token))
    assert got.status_code == 200, got.text
    assert got.json()["crisi"]["trigger_text"] == "loud noise at the market"
    assert got.json()["crisi"]["resolution_text"] == "a quiet corner"


async def test_restore_refused_after_the_window(test_client, db_session, up_ctx):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    await _rebind(db, up_ctx)
    await db.execute(
        text("UPDATE ups SET deleted_at = now() - INTERVAL '7 days 1 minute' WHERE id = :id"),
        {"id": up_id},
    )
    await db.execute(
        text(
            "UPDATE feed_entries SET deleted_at = now() - INTERVAL '7 days 1 minute' "
            "WHERE entity_type = 'up' AND entity_id = :id"
        ),
        {"id": up_id},
    )
    db.expire_all()

    assert (await _list(test_client, up_ctx, token)).json() == {"items": []}
    resp = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert resp.status_code == 410, resp.text
    assert resp.json()["error"]["code"] == "UP_RESTORE_WINDOW_EXPIRED"


async def test_days_left_counts_down(test_client, db_session, up_ctx):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    await _rebind(db, up_ctx)
    await db.execute(
        text("UPDATE ups SET deleted_at = now() - INTERVAL '6 days 12 hours' WHERE id = :id"),
        {"id": up_id},
    )
    db.expire_all()

    (item,) = (await _list(test_client, up_ctx, token)).json()["items"]
    assert item["days_left"] == 1


async def test_moderation_take_down_is_not_restorable(test_client, db_session, up_ctx):
    """A take-down hides the feed row and soft-deletes the UP; the family cannot undo it."""
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)

    await _rebind(db, up_ctx)
    await db.execute(
        text(
            "UPDATE feed_entries SET visible_to_family = false "
            "WHERE entity_type = 'up' AND entity_id = :id"
        ),
        {"id": up_id},
    )
    await db.execute(text("UPDATE ups SET deleted_at = now() WHERE id = :id"), {"id": up_id})
    db.expire_all()

    assert (await _list(test_client, up_ctx, token)).json() == {"items": []}
    resp = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "UP_NOT_FOUND"


async def test_view_only_cannot_list_or_restore(test_client, db_session, up_ctx, second_user):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    await _rebind(db, up_ctx)
    viewer = await _view_only_token(db, up_ctx, second_user)

    listed = await _list(test_client, up_ctx, viewer)
    assert listed.status_code == 403
    assert listed.json()["error"]["code"] == "FORBIDDEN"
    resp = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(viewer))
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "FORBIDDEN"


async def test_no_membership_and_other_tenant_get_404(
    test_client, db_session, up_ctx, second_user, other_family
):
    db = db_session
    token = await _admin_token(up_ctx, db)
    up_id = await _create(test_client, up_ctx, token)
    await _delete(test_client, token, up_id)

    await _rebind(db, up_ctx)
    stranger = await mint_access_token(second_user.id, up_ctx["tenant_id"], db)
    assert (await _list(test_client, up_ctx, stranger)).status_code == 404
    resp = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(stranger))
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "UP_NOT_FOUND"

    await db.execute(text("RESET ROLE"))
    outsider = await mint_access_token(other_family["admin_id"], other_family["tenant_id"], db)
    assert (await _list(test_client, up_ctx, outsider)).status_code == 404
    resp = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(outsider))
    assert resp.status_code == 404

    missing = await test_client.post(f"/api/v1/ups/{uuid.uuid4()}/restore", headers=_hdr(token))
    assert missing.status_code == 404


# ── Restore answers to the profile's state today (decision 17, 2026-10-06) ─────


async def _deleted_up(test_client, db, ctx: dict) -> tuple[str, str]:
    token = await _admin_token(ctx, db)
    up_id = await _create(test_client, ctx, token)
    await _delete(test_client, token, up_id)
    await _rebind(db, ctx)
    return token, up_id


async def _assert_still_deleted(db, ctx: dict, up_id: str) -> None:
    await _rebind(db, ctx)
    db.expire_all()
    row = (
        await db.execute(
            text(
                "SELECT u.deleted_at IS NOT NULL, f.deleted_at IS NOT NULL, "
                "(SELECT count(*) FROM audit_events WHERE event_type = 'up.restored' "
                " AND entity_id = u.id) "
                "FROM ups u JOIN feed_entries f ON f.entity_type = 'up' AND f.entity_id = u.id "
                "WHERE u.id = :id"
            ),
            {"id": up_id},
        )
    ).one()
    assert tuple(row) == (True, True, 0)


async def test_restore_refused_when_ups_consent_was_revoked_after_the_delete(
    test_client, db_session, up_ctx
):
    from app.gdpr.consent import ConsentRepository

    db = db_session
    token, up_id = await _deleted_up(test_client, db, up_ctx)
    await ConsentRepository(db).revoke(
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        revoked_by_user_id=up_ctx["admin_id"],
        scope="ups",
        policy_version="v1",
    )
    await db.flush()

    # The list still shows the UP, with the reason it cannot come back.
    listed = await _list(test_client, up_ctx, token)
    assert listed.status_code == 200, listed.text
    (item,) = listed.json()["items"]
    assert item["id"] == up_id
    assert item["restore_blocked_reason"] == "consent_revoked"

    refused = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert refused.status_code == 403, refused.text
    assert refused.json()["error"]["code"] == "CONSENT_NOT_FOUND"
    await _assert_still_deleted(db, up_ctx, up_id)

    # Consent given again inside the window: the UP can come back.
    await ConsentRepository(db).grant(
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        granted_by_user_id=up_ctx["admin_id"],
        scope="ups",
        basis="parental_authority",
        policy_version="v1",
    )
    await db.flush()
    (item,) = (await _list(test_client, up_ctx, token)).json()["items"]
    assert item["restore_blocked_reason"] is None
    restored = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert restored.status_code == 200, restored.text
    assert restored.json()["was_already"] is False


@pytest.mark.parametrize(
    ("profile_update", "reason", "code"),
    [
        (
            "migration_state = 'initiated', migration_locked_until = now() + interval '72 hours'",
            "profile_migrating",
            "PROFILE_MIGRATION_IN_PROGRESS",
        ),
        (
            "adult_consent_state = 'timed_out'",
            "awaiting_adult_consent",
            "PROFILE_AWAITING_ADULT_CONSENT",
        ),
        ("adult_consent_state = 'erased'", "erasure_requested", "PROFILE_ERASURE_REQUESTED"),
    ],
    ids=["migrate-at-18-lock", "adult-consent-unanswered", "erasure-requested"],
)
async def test_restore_refused_while_the_profile_is_closed_to_writes(
    test_client, db_session, up_ctx, profile_update, reason, code
):
    db = db_session
    token, up_id = await _deleted_up(test_client, db, up_ctx)
    await db.execute(
        text("UPDATE profiles SET " + profile_update + " WHERE id = :id"),
        {"id": str(up_ctx["profile_id"])},
    )
    await db.flush()

    listed = await _list(test_client, up_ctx, token)
    assert listed.status_code == 200, listed.text
    (item,) = listed.json()["items"]
    assert item["id"] == up_id
    assert item["restore_blocked_reason"] == reason

    refused = await test_client.post(f"/api/v1/ups/{up_id}/restore", headers=_hdr(token))
    assert refused.status_code == 423, refused.text
    assert refused.json()["error"]["code"] == code
    await _assert_still_deleted(db, up_ctx, up_id)
