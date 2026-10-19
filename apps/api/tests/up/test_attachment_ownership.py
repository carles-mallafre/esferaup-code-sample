"""UP attachments are owned by the verified upload ledger, never client metadata."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError
from sqlalchemy import text

from app.schemas.up import CrisiData, UPAttachmentRequest, UPCreateRequest
from app.services.up_service import UPService
from app.up.errors import (
    AttachmentRejectedError,
    AudioAttachmentLimitExceededError,
    UPNotFoundError,
)
from app.uploads.pipeline import claim_clean_candidate, promote_clean_candidate_ready
from tests.family.conftest import bind_request_identity
from tests.up.conftest import auth_headers, mint_access_token

pytestmark = pytest.mark.integration

_OWNING_PROFILE = object()


async def _verified_upload(
    db,
    ctx,
    *,
    upload_key: str | None = None,
    profile_id: uuid.UUID | None | object = _OWNING_PROFILE,
    context: str = "up_image",
    status: str = "pending",
) -> str:
    is_audio = context == "up_audio"
    mime = "audio/mp4" if is_audio else "image/jpeg"
    extension = "m4a" if is_audio else "jpg"
    key = upload_key or f"uploads/{uuid.uuid4()}.{extension}"
    await db.execute(
        text(
            "INSERT INTO pending_uploads "
            "(id, tenant_id, profile_id, upload_key, context, mime, "
            "size_bytes_reserved, sha256_content_address, pipeline_status, expires_at, "
            "clean_object_key, verified_sha256, verified_size_bytes) "
            "VALUES (:id, :tid, :pid, :key, :context, :mime, 1024, :sha, "
            "CAST(:status AS uploadstatus), NULL, :clean, :verified_sha, :verified_size)"
        ),
        {
            "id": str(uuid.uuid4()),
            "tid": str(ctx["tenant_id"]),
            "pid": (
                str(ctx["profile_id"])
                if profile_id is _OWNING_PROFILE
                else str(profile_id)
                if profile_id is not None
                else None
            ),
            "key": key,
            "context": context,
            "mime": mime,
            "sha": "a" * 64,
            "status": status,
            "clean": (
                f"tenant_{ctx['tenant_id']}/_internal/clean/{uuid.uuid4().hex}.{extension}"
                if status == "ready"
                else None
            ),
            "verified_sha": "b" * 64 if status == "ready" else None,
            "verified_size": 900 if status == "ready" else None,
        },
    )
    return key


async def _insert_subscription(db, tenant_id: uuid.UUID, *, tier: str, status: str) -> None:
    await db.execute(
        text(
            "INSERT INTO subscriptions (id, tenant_id, tier, status, provider) "
            "VALUES (:id, :tid, cast(:tier as subscriptiontier), "
            "cast(:status as subscriptionstatus), 'stripe')"
        ),
        {
            "id": str(uuid.uuid4()),
            "tid": str(tenant_id),
            "tier": tier,
            "status": status,
        },
    )


def _request(upload_key: str) -> UPCreateRequest:
    return UPCreateRequest(
        category="casa",
        occurred_at=datetime.now(UTC),
        attachments=[UPAttachmentRequest(upload_key=upload_key)],
    )


def _request_many(*upload_keys: str) -> UPCreateRequest:
    return UPCreateRequest(
        category="casa",
        occurred_at=datetime.now(UTC),
        attachments=[UPAttachmentRequest(upload_key=key) for key in upload_keys],
    )


def test_attachment_schema_rejects_client_owned_metadata() -> None:
    with pytest.raises(ValidationError):
        UPCreateRequest.model_validate(
            {
                "category": "casa",
                "occurred_at": datetime.now(UTC),
                "attachments": [{"upload_key": "k", "mime": "image/jpeg"}],
            }
        )


async def test_pending_attachment_is_linked_hidden_and_queued(up_ctx, test_client):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx)

    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )

    linked = (
        await db.execute(
            text(
                "SELECT linked_up_id, linked_up_position FROM pending_uploads "
                "WHERE upload_key = :key"
            ),
            {"key": key},
        )
    ).one()
    assert linked.linked_up_id == result.id
    assert linked.linked_up_position == 0
    assert (
        await db.execute(
            text("SELECT has_attachment FROM feed_entries WHERE entity_id = :id"),
            {"id": str(result.id)},
        )
    ).scalar_one() is False
    assert (
        await db.execute(
            text(
                "SELECT count(*) FROM outbox_events "
                "WHERE event_type = 'upload.scan_requested' AND payload->>'upload_key' = :key"
            ),
            {"key": key},
        )
    ).scalar_one() == 1
    response = await UPService(db).get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert response["attachments"] == []
    assert response["attachments_pending"] is True
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    http = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert http.status_code == 200, http.text
    assert http.json()["attachments"] == []
    assert http.json()["attachments_pending"] is True


async def test_clean_promotion_reveals_only_verified_candidate(up_ctx, test_client):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx)
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )
    candidate = f"tenant_{up_ctx['tenant_id']}/_internal/clean/{uuid.uuid4().hex}.jpg"
    assert await claim_clean_candidate(db, up_ctx["tenant_id"], key, candidate) == candidate
    promoted = await promote_clean_candidate_ready(
        db,
        up_ctx["tenant_id"],
        key,
        candidate,
        "c" * 64,
        777,
    )
    assert promoted.linked_up_id == result.id

    response = await UPService(db).get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert response["attachments"] == [
        {
            "attachment_index": 0,
            "upload_key": key,
            "mime": "image/jpeg",
            "size_bytes": 777,
        }
    ]
    assert response["attachments_pending"] is False
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    http = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert http.status_code == 200, http.text
    assert http.json()["attachments_pending"] is False
    assert [item["attachment_index"] for item in http.json()["attachments"]] == [0]
    assert http.json()["attachments"][0]["size_bytes"] == 777
    assert (
        await db.execute(
            text("SELECT has_attachment FROM feed_entries WHERE entity_id = :id"),
            {"id": str(result.id)},
        )
    ).scalar_one() is True


async def test_attachment_download_grant_uses_clean_candidate_and_hides_key(up_ctx):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )

    grant = await UPService(db).create_attachment_download_grant(
        up_ctx["tenant_id"], result.id, 0, user_id=up_ctx["admin_id"]
    )

    assert grant["mime"] == "image/jpeg"
    assert grant["size_bytes"] == 900
    assert "download_url" in grant
    assert "upload_key" not in grant


@pytest.mark.parametrize("status", ["pending", "quarantined", "rejected", "pending_admin_review"])
async def test_attachment_download_grant_is_opaque_until_ready(up_ctx, status):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx)
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )
    await db.execute(
        text(
            "UPDATE pending_uploads SET pipeline_status = CAST(:status AS uploadstatus) "
            "WHERE upload_key = :key"
        ),
        {"status": status, "key": key},
    )

    with pytest.raises(UPNotFoundError):
        await UPService(db).create_attachment_download_grant(
            up_ctx["tenant_id"], result.id, 0, user_id=up_ctx["admin_id"]
        )

    response = await UPService(db).get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert response["attachments"] == []
    assert response["attachments_pending"] is (status == "pending")


async def test_attachment_download_grant_out_of_range_is_opaque(up_ctx):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )

    with pytest.raises(UPNotFoundError):
        await UPService(db).create_attachment_download_grant(
            up_ctx["tenant_id"], result.id, 1, user_id=up_ctx["admin_id"]
        )


async def test_attachment_indexes_do_not_shift_while_an_earlier_scan_is_pending(
    up_ctx, test_client
):
    db = up_ctx["db"]
    pending_key = await _verified_upload(db, up_ctx)
    ready_key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request_many(pending_key, ready_key),
    )

    response = await UPService(db).get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert [attachment["attachment_index"] for attachment in response["attachments"]] == [1]
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    http = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert http.status_code == 200, http.text
    assert [item["attachment_index"] for item in http.json()["attachments"]] == [1]

    media = (
        await db.execute(
            text("SELECT photo_count, cover_image_index FROM feed_entries WHERE entity_id = :id"),
            {"id": result.id},
        )
    ).one()
    assert tuple(media) == (1, 1)

    with pytest.raises(UPNotFoundError):
        await UPService(db).create_attachment_download_grant(
            up_ctx["tenant_id"], result.id, 0, user_id=up_ctx["admin_id"]
        )
    grant = await UPService(db).create_attachment_download_grant(
        up_ctx["tenant_id"], result.id, 1, user_id=up_ctx["admin_id"]
    )
    assert grant["size_bytes"] == 900

    candidate = f"tenant_{up_ctx['tenant_id']}/_internal/clean/{uuid.uuid4().hex}.jpg"
    assert await claim_clean_candidate(db, up_ctx["tenant_id"], pending_key, candidate) == candidate
    await promote_clean_candidate_ready(
        db,
        up_ctx["tenant_id"],
        pending_key,
        candidate,
        "d" * 64,
        811,
    )
    response = await UPService(db).get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert [attachment["attachment_index"] for attachment in response["attachments"]] == [0, 1]
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    http = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert http.status_code == 200, http.text
    assert [item["attachment_index"] for item in http.json()["attachments"]] == [0, 1]
    media = (
        await db.execute(
            text("SELECT photo_count, cover_image_index FROM feed_entries WHERE entity_id = :id"),
            {"id": result.id},
        )
    ).one()
    assert tuple(media) == (2, 0)
    unchanged = await UPService(db).create_attachment_download_grant(
        up_ctx["tenant_id"], result.id, 1, user_id=up_ctx["admin_id"]
    )
    assert unchanged["size_bytes"] == 900


async def test_attachment_download_http_is_private_and_keyless(test_client, up_ctx):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)

    response = await test_client.get(
        f"/api/v1/ups/{result.id}/attachments/0/download",
        headers=auth_headers(token),
    )

    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "private, no-store"
    assert response.json()["mime"] == "image/jpeg"
    assert "upload_key" not in response.json()


async def test_attachment_download_http_hides_same_tenant_membership(
    test_client, up_ctx, second_user
):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )
    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], db)

    response = await test_client.get(
        f"/api/v1/ups/{result.id}/attachments/0/download",
        headers=auth_headers(token),
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "UP_NOT_FOUND"


async def test_up_detail_http_hides_missing_same_tenant_profile_membership(
    test_client, up_ctx, second_user
):
    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at=datetime.now(UTC)),
    )
    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], up_ctx["db"])

    response = await test_client.get(
        f"/api/v1/ups/{result.id}",
        headers=auth_headers(token),
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "UP_NOT_FOUND"


@pytest.mark.parametrize(
    ("method", "suffix", "body"),
    [
        ("PATCH", "", {"mood": "happy"}),
        ("DELETE", "", None),
        ("POST", "/pin-memory", None),
        ("POST", "/unpin-memory", None),
    ],
)
async def test_up_uuid_mutations_require_live_profile_membership(
    test_client,
    up_ctx,
    second_user,
    method,
    suffix,
    body,
):
    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at=datetime.now(UTC)),
    )
    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], up_ctx["db"])
    response = await test_client.request(
        method,
        f"/api/v1/ups/{result.id}{suffix}",
        headers={**auth_headers(token), "Idempotency-Key": str(uuid.uuid4())},
        json=body,
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "UP_NOT_FOUND"


@pytest.mark.parametrize(
    ("method", "suffix", "body"),
    [
        ("PATCH", "", {"mood": "happy"}),
        ("DELETE", "", None),
        ("POST", "/pin-memory", None),
        ("POST", "/unpin-memory", None),
    ],
)
async def test_view_only_member_can_read_but_cannot_mutate_up(
    test_client, up_ctx, second_user, method, suffix, body
):
    from app.services.family_service import FamilyService

    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at=datetime.now(UTC)),
    )
    family = FamilyService(up_ctx["db"])
    invitation = await family.invite_member(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        email=second_user._test_email,
        role="view_only",
    )
    await bind_request_identity(up_ctx["db"], up_ctx["tenant_id"], second_user.id)
    await family.accept_invite(
        up_ctx["tenant_id"],
        second_user.id,
        token=invitation["invite_token"],
    )
    token = await mint_access_token(second_user.id, up_ctx["tenant_id"], up_ctx["db"])

    readable = await test_client.get(
        f"/api/v1/ups/{result.id}",
        headers=auth_headers(token),
    )
    denied = await test_client.request(
        method,
        f"/api/v1/ups/{result.id}{suffix}",
        headers={**auth_headers(token), "Idempotency-Key": str(uuid.uuid4())},
        json=body,
    )

    assert readable.status_code == 200
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "FORBIDDEN"
    unchanged = await test_client.get(f"/api/v1/ups/{result.id}", headers=auth_headers(token))
    assert unchanged.status_code == 200
    assert unchanged.json() == readable.json()


async def test_attachment_download_http_hides_cross_tenant(test_client, up_ctx, other_family):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    result = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request(key),
    )
    token = await mint_access_token(other_family["admin_id"], other_family["tenant_id"], db)

    response = await test_client.get(
        f"/api/v1/ups/{result.id}/attachments/0/download",
        headers=auth_headers(token),
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "UP_NOT_FOUND"


async def test_internal_admin_has_no_family_content_authority(test_client, up_ctx):
    from tests.crm.conftest import make_internal_admin

    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    up = await UPService(db).create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _request(key)
    )
    admin = await make_internal_admin(db)
    await db.execute(
        text(
            "UPDATE users SET is_verified=true, email_verified_at=now(), "
            "email_verification_used_at=now() WHERE id=:id"
        ),
        {"id": admin["user_id"]},
    )
    token = await mint_access_token(admin["user_id"], admin["tenant_id"], db)
    headers = auth_headers(token)
    for method, path, body in (
        ("GET", f"/api/v1/ups/{up.id}", None),
        ("GET", f"/api/v1/ups/{up.id}/attachments/0/download", None),
        ("PATCH", f"/api/v1/ups/{up.id}", {"mood": "happy"}),
    ):
        response = await test_client.request(
            method, path, headers={**headers, "Idempotency-Key": str(uuid.uuid4())}, json=body
        )
        assert response.status_code == 404, response.text
        assert response.json()["error"]["code"] == "UP_NOT_FOUND"
    owner_token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    owned = await test_client.get(f"/api/v1/ups/{up.id}", headers=auth_headers(owner_token))
    assert owned.status_code == 200, owned.text
    assert owned.json()["mood"] != "happy"


async def test_history_only_http_reads_old_up_and_refuses_new_data_and_writes(
    test_client, up_ctx, second_user
):
    from app.models.up import UP
    from tests.factories.profile import FamilyMembershipFactory

    db = up_ctx["db"]
    cutoff = datetime.now(UTC) - timedelta(days=1)
    old = UP(
        id=uuid.uuid4(),
        tenant_id=up_ctx["tenant_id"],
        profile_id=up_ctx["profile_id"],
        author_user_id=up_ctx["admin_id"],
        category="casa",
        note_plain="QA histórica",
        occurred_at=cutoff - timedelta(hours=1),
        created_at=cutoff - timedelta(hours=1),
        updated_at=cutoff - timedelta(hours=1),
    )
    db.add(old)
    await db.flush()
    new = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(category="casa", occurred_at=datetime.now(UTC)),
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
    before = await test_client.get(f"/api/v1/ups/{old.id}", headers=headers)
    assert before.status_code == 200, before.text
    hidden = await test_client.get(f"/api/v1/ups/{new.id}", headers=headers)
    assert hidden.status_code == 404, hidden.text
    assert hidden.json()["error"]["code"] == "UP_NOT_FOUND"
    for method, url, body in (
        ("PATCH", f"/api/v1/ups/{old.id}", {"mood": "happy"}),
        ("DELETE", f"/api/v1/ups/{old.id}", None),
        ("POST", f"/api/v1/ups/{old.id}/pin-memory", None),
        ("POST", f"/api/v1/ups/{old.id}/unpin-memory", None),
        (
            "POST",
            f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
            {"category": "casa", "occurred_at": datetime.now(UTC).isoformat()},
        ),
    ):
        response = await test_client.request(
            method, url, headers={**headers, "Idempotency-Key": str(uuid.uuid4())}, json=body
        )
        assert response.status_code == 403, response.text
        assert response.json()["error"]["code"] == "FORBIDDEN"
    unchanged = await test_client.get(f"/api/v1/ups/{old.id}", headers=headers)
    assert unchanged.status_code == 200
    assert unchanged.json() == before.json()


@pytest.mark.parametrize(
    "blocked_state,expected_code",
    [
        ("handoff", "PROFILE_MIGRATION_IN_PROGRESS"),
        ("handoff_expired", "PROFILE_MIGRATION_IN_PROGRESS"),
        ("timed_out", "PROFILE_AWAITING_ADULT_CONSENT"),
        ("erased", "PROFILE_ERASURE_REQUESTED"),
    ],
)
@pytest.mark.parametrize("is_crisi", [False, True])
async def test_profile_write_state_blocks_up_mutations(
    test_client, up_ctx, blocked_state, expected_code, is_crisi
):
    db = up_ctx["db"]
    up = await UPService(db).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        UPCreateRequest(
            category="emocions" if is_crisi else "casa",
            occurred_at=datetime.now(UTC),
            is_crisi=is_crisi,
            crisi=CrisiData(trigger_text="QA synthetic", duration_bucket="lt5")
            if is_crisi
            else None,
        ),
    )
    if blocked_state.startswith("handoff"):
        await db.execute(
            text(
                "UPDATE profiles SET migration_state='initiated', migration_locked_until=:until "
                "WHERE id=:pid"
            ),
            {
                "pid": up_ctx["profile_id"],
                "until": datetime.now(UTC)
                + timedelta(days=-1 if blocked_state == "handoff_expired" else 1),
            },
        )
    else:
        await db.execute(
            text("UPDATE profiles SET adult_consent_state=:state WHERE id=:pid"),
            {"pid": up_ctx["profile_id"], "state": blocked_state},
        )
    token = await mint_access_token(up_ctx["admin_id"], up_ctx["tenant_id"], db)
    headers = auth_headers(token)
    before = await test_client.get(f"/api/v1/ups/{up.id}", headers=headers)
    assert before.status_code == 200, before.text
    mutations = [
        ("PATCH", f"/api/v1/ups/{up.id}", {"mood": "happy"}),
        ("DELETE", f"/api/v1/ups/{up.id}", None),
        ("POST", f"/api/v1/ups/{up.id}/pin-memory", None),
        ("POST", f"/api/v1/ups/{up.id}/unpin-memory", None),
        (
            "POST",
            f"/api/v1/profiles/{up_ctx['profile_id']}/ups",
            {"category": "casa", "occurred_at": datetime.now(UTC).isoformat()},
        ),
    ]
    if is_crisi:
        mutations.append(("POST", f"/api/v1/ups/{up.id}/crisi/redact", {}))
    for method, url, body in mutations:
        response = await test_client.request(
            method, url, headers={**headers, "Idempotency-Key": str(uuid.uuid4())}, json=body
        )
        assert response.status_code == 423, response.text
        assert response.json()["error"]["code"] == expected_code
    unchanged = await test_client.get(f"/api/v1/ups/{up.id}", headers=headers)
    assert unchanged.status_code == 200
    assert unchanged.json() == before.json()


@pytest.mark.parametrize("mismatch", ["profile", "context", "unverified", "terminal"])
async def test_attachment_boundary_rejects_mismatch(up_ctx, mismatch):
    db = up_ctx["db"]
    kwargs = {}
    if mismatch == "context":
        kwargs["context"] = "obs_attachment"
    elif mismatch == "terminal":
        kwargs["status"] = "quarantined"
    elif mismatch == "profile":
        kwargs["profile_id"] = None
    key = await _verified_upload(db, up_ctx, **kwargs)
    if mismatch == "unverified":
        await db.execute(
            text(
                "UPDATE pending_uploads SET expires_at = now() + interval '5 minutes' "
                "WHERE upload_key = :key"
            ),
            {"key": key},
        )

    with pytest.raises(AttachmentRejectedError):
        async with db.begin_nested():
            await UPService(db).create_up(
                up_ctx["tenant_id"],
                up_ctx["profile_id"],
                up_ctx["admin_id"],
                _request(key),
            )


async def test_upload_key_cannot_be_reused_by_two_ups(up_ctx):
    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, status="ready")
    await UPService(db).create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _request(key)
    )
    with pytest.raises(AttachmentRejectedError):
        async with db.begin_nested():
            await UPService(db).create_up(
                up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _request(key)
            )


async def test_free_up_rejects_a_second_audio_attachment(up_ctx):
    first = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")
    second = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")

    with pytest.raises(AudioAttachmentLimitExceededError) as exc:
        await UPService(up_ctx["db"]).create_up(
            up_ctx["tenant_id"],
            up_ctx["profile_id"],
            up_ctx["admin_id"],
            _request_many(first, second),
        )

    assert exc.value.details == [{"audio_limit": 1}]


async def test_entitled_premium_up_accepts_two_audio_attachments(up_ctx):
    await _insert_subscription(up_ctx["db"], up_ctx["tenant_id"], tier="premium", status="active")
    first = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")
    second = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")

    result = await UPService(up_ctx["db"]).create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _request_many(first, second),
    )

    contexts = (
        (
            await up_ctx["db"].execute(
                text(
                    "SELECT context FROM pending_uploads WHERE linked_up_id = :up_id "
                    "ORDER BY linked_up_position"
                ),
                {"up_id": str(result.id)},
            )
        )
        .scalars()
        .all()
    )
    assert contexts == ["up_audio", "up_audio"]


@pytest.mark.parametrize("status", ["past_due", "cancelled", "expired"])
async def test_lapsed_premium_up_rejects_a_second_audio_attachment(up_ctx, status):
    await _insert_subscription(up_ctx["db"], up_ctx["tenant_id"], tier="premium", status=status)
    first = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")
    second = await _verified_upload(up_ctx["db"], up_ctx, context="up_audio")

    with pytest.raises(AudioAttachmentLimitExceededError):
        await UPService(up_ctx["db"]).create_up(
            up_ctx["tenant_id"],
            up_ctx["profile_id"],
            up_ctx["admin_id"],
            _request_many(first, second),
        )


@pytest.mark.parametrize("context,media", [("up_image", "photo"), ("up_audio", "audio")])
async def test_feed_media_filter_waits_for_ready_and_survives_linking(up_ctx, context, media):
    from app.services.feed_read_service import FeedReadService

    db = up_ctx["db"]
    key = await _verified_upload(db, up_ctx, context=context)
    up = await UPService(db).create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _request(key)
    )
    service = FeedReadService(db)
    args = dict(user_id=up_ctx["admin_id"], media=media)
    pending = await service.list_feed(up_ctx["tenant_id"], up_ctx["profile_id"], **args)
    assert pending.data == []
    extension = "m4a" if context == "up_audio" else "jpg"
    candidate = f"tenant_{up_ctx['tenant_id']}/_internal/clean/{uuid.uuid4().hex}.{extension}"
    await claim_clean_candidate(db, up_ctx["tenant_id"], key, candidate_key=candidate)
    await promote_clean_candidate_ready(
        db,
        up_ctx["tenant_id"],
        key,
        candidate_key=candidate,
        verified_sha256="b" * 64,
        verified_size_bytes=900,
    )
    ready = await service.list_feed(up_ctx["tenant_id"], up_ctx["profile_id"], **args)
    assert [item.entity_id for item in ready.data] == [up.id]
    assert ready.stats.matching_count == 1
    another_key = await _verified_upload(db, up_ctx, context=context, status="ready")
    another = await UPService(db).create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _request(another_key)
    )
    page = await service.list_feed(up_ctx["tenant_id"], up_ctx["profile_id"], **args)
    assert {item.entity_id for item in page.data} == {up.id, another.id}
