"""Plan 019 — UP + Crisi DPIA 5-set + idempotency over HTTP (real RS256 tokens).

DPIA per Art-9 endpoint (POST /v1/profiles/{id}/ups AND POST .../crisis):
  401 (no token), 404 default-deny (no membership), 403 (insufficient role:
  view_only), tenant-isolation (cross-tenant → 404), audit-emitted.
Plus: idempotency-key dedup, consent-403 over HTTP, pin idempotency, is_crisi 422.

These tests drive the ASGI app via test_client; the get_db override shares the
test's rolled-back db_session so DB assertions see the same data.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from sqlalchemy import text

from tests.family.conftest import bind_request_identity
from tests.idempotency_keys import idempotency_key
from tests.up.conftest import auth_headers, grant_ups_consent, mint_access_token, revoke_ups_consent

pytestmark = pytest.mark.integration


def _hdr(token: str, idem: str) -> dict:
    return {**auth_headers(token), "Idempotency-Key": idempotency_key(idem)}


def _body(**kw) -> dict:
    base = {
        "category": "casa",
        "occurred_at": "2026-05-26T10:00:00Z",
        "note": "built a tower",
    }
    base.update(kw)
    return base


async def test_points_daily_cap_is_profile_scoped_over_http(test_client, up_ctx):
    from app.services.profile_service import ProfileService

    db = up_ctx["db"]
    tid, uid, pid = up_ctx["tenant_id"], up_ctx["admin_id"], up_ctx["profile_id"]
    sibling = await ProfileService(db).create_profile(
        tid, uid, display_name="QA sibling", dob=datetime(2019, 1, 1, tzinfo=UTC), is_child=True
    )
    await grant_ups_consent(db, tid, sibling.id, uid)
    token = await mint_access_token(uid, tid, db)
    awards = []
    for index in range(7):
        response = await test_client.post(
            f"/api/v1/profiles/{pid}/ups",
            headers=_hdr(token, f"daily-cap-{index}"),
            json=_body(),
        )
        assert response.status_code == 201, response.text
        awards.append(response.json()["punts_awarded"])
    assert awards == [5, 5, 5, 5, 5, 0, 0]
    sibling_response = await test_client.post(
        f"/api/v1/profiles/{sibling.id}/ups",
        headers=_hdr(token, "daily-cap-sibling"),
        json=_body(),
    )
    assert sibling_response.status_code == 201, sibling_response.text
    assert sibling_response.json()["punts_awarded"] == 5
    await bind_request_identity(db, tid, uid)
    rows = (
        await db.execute(
            text(
                "SELECT profile_id, count(*), sum(delta) FROM points_ledger "
                "WHERE tenant_id=:tid AND reason='note_crisi' GROUP BY profile_id"
            ),
            {"tid": tid},
        )
    ).all()
    assert {row[0]: (row[1], row[2]) for row in rows} == {
        pid: (5, 25),
        sibling.id: (1, 5),
    }


# ── 401: no token ────────────────────────────────────────────────────────────


async def test_create_up_requires_auth(test_client, up_ctx):
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
        headers={"Idempotency-Key": idempotency_key("no-auth-1")},
        json=_body(),
    )
    assert resp.status_code == 401


async def test_create_crisi_requires_auth(test_client, up_ctx):
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/crisis",
        headers={"Idempotency-Key": idempotency_key("no-auth-2")},
        json={"occurred_at": "2026-05-26T10:00:00Z", "trigger_text": "x"},
    )
    assert resp.status_code == 401


# ── 404 default-deny: caller has no membership on the profile ───────────────────


async def test_create_up_no_membership_404(test_client, db_session, up_ctx, second_user):
    """A same-tenant member posting to an unshared profile gets no oracle."""
    from datetime import UTC, datetime

    from app.services.family_service import FamilyService
    from app.services.profile_service import ProfileService

    db = db_session
    tenant_id = up_ctx["tenant_id"]
    shared_profile = await ProfileService(db).create_profile(
        tenant_id,
        up_ctx["admin_id"],
        display_name="Shared sibling",
        dob=datetime(2019, 1, 1, tzinfo=UTC),
        is_child=True,
    )
    invite = await FamilyService(db).invite_member(
        tenant_id,
        shared_profile.id,
        up_ctx["admin_id"],
        email=second_user._test_email,
        role="view_only",
    )
    await bind_request_identity(db, tenant_id, second_user.id)
    await FamilyService(db).accept_invite(
        tenant_id,
        second_user.id,
        token=invite["invite_token"],
    )
    token = await mint_access_token(second_user.id, tenant_id, db)
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
        headers=_hdr(token, "nm-1"),
        json=_body(),
    )
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"


# ── 403: insufficient role (view_only cannot create) ───────────────────────────


async def test_view_only_cannot_create_up(test_client, db_session, up_ctx, second_user):
    db = db_session
    from app.services.family_service import FamilyService

    svc = FamilyService(db)
    inv = await svc.invite_member(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        email=second_user._test_email,
        role="view_only",
    )
    await bind_request_identity(db, up_ctx["tenant_id"], second_user.id)
    await svc.accept_invite(up_ctx["tenant_id"], second_user.id, token=inv["invite_token"])
    await db.flush()

    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], db)
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
        headers=_hdr(token, "vo-1"),
        json=_body(),
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "FORBIDDEN"


# ── tenant-isolation: GET a UP from another tenant → 404 ───────────────────────


async def test_get_up_cross_tenant_404(test_client, db_session, up_ctx, other_family):
    """Create a UP in up_ctx, then try to GET it with the other family's token
    scoped to the other tenant → 404 (tenant isolation)."""
    db = db_session
    # Create a UP as the up_ctx admin (service layer; consent already granted).
    from app.schemas.up import UPCreateRequest
    from app.services.up_service import UPService

    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at="2026-05-26T10:00:00Z", note="x"),
    )
    await db.flush()

    other_token = await mint_access_token(other_family["admin_id"], other_family["tenant_id"], db)
    resp = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(other_token))
    assert resp.status_code == 404


# ── audit-emitted (over HTTP) ──────────────────────────────────────────────────


async def test_create_up_emits_audit_http(test_client, db_session, up_ctx):
    db = db_session
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
        headers=_hdr(token, "audit-1"),
        json=_body(category="esport"),
    )
    assert resp.status_code == 201, resp.text
    up_id = resp.json()["id"]
    n = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up.created' AND entity_id = :eid"
            ),
            {"eid": up_id},
        )
    ).scalar_one()
    assert n == 1


async def test_create_crisi_emits_audit_http(test_client, db_session, up_ctx):
    db = db_session
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    resp = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/crisis",
        headers=_hdr(token, "crisi-audit-1"),
        json={
            "occurred_at": "2026-05-26T10:00:00Z",
            "trigger_text": "loud party next door",
            "duration_bucket": "five_to_15",
        },
    )
    assert resp.status_code == 201, resp.text
    up_id = resp.json()["up_id"]
    n = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up_crisi.created' AND entity_id = :eid"
            ),
            {"eid": up_id},
        )
    ).scalar_one()
    assert n == 1
    # The sidecar exists with encrypted trigger.
    trig = (
        await db.execute(text("SELECT trigger_text FROM up_crisi WHERE up_id = :id"), {"id": up_id})
    ).scalar_one()
    assert trig is not None and len(trig) > 0


# ── consent 403 over HTTP (no 'ups' consent) ──────────────────────────────────


async def test_create_up_without_consent_403_http(test_client, db_session, family_ctx):
    """A profile whose 'ups' consent was revoked → POST returns 403."""
    db = db_session
    await revoke_ups_consent(
        db, family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    )
    token = await mint_access_token(family_ctx["admin_id"], family_ctx["tenant_id"], db)
    resp = await test_client.post(
        f"/api/v1/profiles/{family_ctx['profile_id']}/ups",
        headers=_hdr(token, "noconsent-1"),
        json=_body(),
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "CONSENT_NOT_FOUND"

    # Grant consent → now 201.
    await grant_ups_consent(
        db, family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    )
    ok = await test_client.post(
        f"/api/v1/profiles/{family_ctx['profile_id']}/ups",
        headers=_hdr(token, "consent-ok-1"),
        json=_body(),
    )
    assert ok.status_code == 201, ok.text


# ── idempotency-key: same key twice → one UP, identical 201 ────────────────────


async def test_idempotency_key(test_client, db_session, up_ctx):
    db = db_session
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    headers = _hdr(token, "idem-fixed")
    body = _body(category="esport", note="same note")

    r1 = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups", headers=headers, json=body
    )
    assert r1.status_code == 201, r1.text
    r2 = await test_client.post(
        f"/api/v1/profiles/{up_ctx['profile_id']}/ups", headers=headers, json=body
    )
    assert r2.status_code == 201, r2.text
    assert r1.json() == r2.json()  # identical response

    # Exactly one UP row was created for this profile+esport in this window.
    n = (
        await db.execute(
            text("SELECT count(*) FROM ups WHERE profile_id = :pid AND category = 'esport'"),
            {"pid": str(up_ctx["profile_id"])},
        )
    ).scalar_one()
    assert n == 1


# ── pin idempotent over HTTP ───────────────────────────────────────────────────


async def test_pin_idempotent_http(test_client, db_session, up_ctx):
    db = db_session
    from app.schemas.up import UPCreateRequest
    from app.services.up_service import UPService

    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at="2026-05-26T10:00:00Z", note="x"),
    )
    await db.commit()
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)

    r1 = await test_client.post(f"/api/v1/ups/{result.id}/pin-memory", headers=_hdr(token, "pin-1"))
    assert r1.status_code == 200, r1.text
    assert r1.json() == {"is_pinned": True, "was_already": False}

    r2 = await test_client.post(f"/api/v1/ups/{result.id}/pin-memory", headers=_hdr(token, "pin-2"))
    assert r2.status_code == 200, r2.text  # idempotent — NOT 409
    assert r2.json() == {"is_pinned": True, "was_already": True}


# ── PATCH flipping is_crisi → 422 over HTTP ────────────────────────────────────


async def test_patch_is_crisi_immutable_http(test_client, db_session, up_ctx):
    db = db_session
    from app.schemas.up import UPCreateRequest
    from app.services.up_service import UPService

    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at="2026-05-26T10:00:00Z", note="x"),
    )
    await db.commit()
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)

    resp = await test_client.patch(
        f"/api/v1/ups/{result.id}",
        headers=_hdr(token, "patch-crisi-1"),
        json={"is_crisi": True},
    )
    assert resp.status_code == 422, resp.text
    assert resp.json()["error"]["code"] == "IS_CRISI_IMMUTABLE_AFTER_CREATE"


# ── special-category access log on Art-9 GET over HTTP ─────────────────────────


async def test_special_category_log_on_art9_get_http(test_client, db_session, up_ctx):
    db = db_session
    from app.schemas.up import CrisiData, UPCreateRequest
    from app.services.up_service import UPService

    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(
            category="emocions",
            occurred_at="2026-05-26T10:00:00Z",
            is_crisi=True,
            crisi=CrisiData(trigger_text="x", duration_bucket="lt5"),
        ),
    )
    await db.commit()
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)

    before = (
        await db.execute(
            text("SELECT count(*) FROM special_category_access_log WHERE entity_id = :id"),
            {"id": str(result.id)},
        )
    ).scalar_one()
    resp = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert resp.status_code == 200, resp.text
    after = (
        await db.execute(
            text("SELECT count(*) FROM special_category_access_log WHERE entity_id = :id"),
            {"id": str(result.id)},
        )
    ).scalar_one()
    assert after == before + 1
