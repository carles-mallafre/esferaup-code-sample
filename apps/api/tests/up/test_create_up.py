"""Plan 019 — UPService.create_up core invariants (service-layer, real Postgres).

Covers: basic create (UP+FeedEntry+EsferaRadius+PointsLedger+outbox), crisi create
(encrypted sidecar), deferred trigger, single-TX atomicity, KMS-failure-no-rows
(prepare-before-persist), Art-9 never-plaintext, points daily cap, idempotent pin,
patch is_crisi immutability + Art-9 category transition, consent gate, save_to_arxiu
outbox sub-event, and the special-category access log on Art-9 read.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import text

from app.errors import KmsUnavailableError
from app.gdpr.consent import ConsentNotFoundError
from app.schemas.up import CrisiData, UPCreateRequest, UPPatchRequest
from app.services.up_service import UPService
from app.up.errors import IsCrisiImmutableError, NotACrisiError
from tests.up.conftest import grant_ups_consent, revoke_ups_consent

pytestmark = pytest.mark.integration


def _req(**kw) -> UPCreateRequest:
    base = {
        "category": "casa",
        "occurred_at": datetime.now(UTC),
        "note": "Marc va construir una torre",
    }
    base.update(kw)
    return UPCreateRequest(**base)


async def _count(db, table: str, **where) -> int:
    clause = " AND ".join(f"{k} = :{k}" for k in where) or "TRUE"
    params = {k: str(v) for k, v in where.items()}
    sql = f"SELECT count(*) FROM {table} WHERE {clause}"
    row = await db.execute(text(sql), params)
    return int(row.scalar_one())


# ── basic happy path ─────────────────────────────────────────────────────────


async def test_create_up_basic(up_ctx):
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req(category="esport")
    )
    await db.flush()

    assert result.punts_awarded == 5
    assert result.daily_cap_reached is False
    assert result.esfera_counts.get("esport") == 1

    assert await _count(db, "ups", id=result.id) == 1
    assert await _count(db, "feed_entries", entity_id=result.id) == 1
    assert await _count(db, "esfera_radius", profile_id=up_ctx["profile_id"]) == 1
    assert await _count(db, "points_ledger", reference_id=result.id) == 1
    assert await _count(db, "outbox_events", idempotency_key=result.id) == 1

    # Primary outbox event type for a non-crisi UP.
    etype = (
        await db.execute(
            text("SELECT event_type FROM outbox_events WHERE idempotency_key = :k"),
            {"k": str(result.id)},
        )
    ).scalar_one()
    assert etype == "up.created"


async def test_create_up_basic_audit_emitted(up_ctx):
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req()
    )
    await db.flush()
    n = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up.created' AND entity_id = :eid"
            ),
            {"eid": str(result.id)},
        )
    ).scalar_one()
    assert n == 1


# ── crisi create ────────────────────────────────────────────────────────────


async def test_create_up_crisi(up_ctx):
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(
            category="emocions",
            is_crisi=True,
            crisi=CrisiData(
                trigger_text="too much noise at the supermarket",
                resolution_text="we went outside and it passed",
                duration_bucket="five_to_15",
                mood_after="happy",
            ),
        ),
    )
    await db.flush()

    # Sidecar exists with NON-NULL encrypted fields (deferred trigger did NOT raise).
    row = (
        await db.execute(
            text(
                "SELECT trigger_text, resolution_text, duration_bucket "
                "FROM up_crisi WHERE up_id = :id"
            ),
            {"id": str(result.id)},
        )
    ).first()
    assert row is not None
    assert row[0] is not None and len(row[0]) > 0  # trigger encrypted
    assert row[1] is not None and len(row[1]) > 0  # resolution encrypted
    assert row[2] == "five_to_15"

    # Outbox event type is the crisi variant.
    etype = (
        await db.execute(
            text("SELECT event_type FROM outbox_events WHERE idempotency_key = :k"),
            {"k": str(result.id)},
        )
    ).scalar_one()
    assert etype == "up.crisi.created"


async def test_crisi_deferred_trigger(up_ctx):
    """A UP(is_crisi=True) with NO up_crisi sidecar must raise when the deferred
    constraint trigger is checked (it is DEFERRABLE INITIALLY DEFERRED). The note
    CHECK is satisfied (emocions → note_encrypted non-null) so the failure is
    specifically the missing sidecar, not the note constraint."""
    db = up_ctx["db"]
    up_id = uuid.uuid4()
    # emocions is Art-9 → must use note_encrypted (the note_art9_must_be_encrypted
    # CHECK forbids note_plain here); a dummy ciphertext satisfies note_exactly_one.
    await db.execute(
        text(
            "INSERT INTO ups (id, tenant_id, profile_id, author_user_id, category, "
            "occurred_at, note_plain, note_encrypted, is_crisi) "
            "VALUES (:id, :tid, :pid, :uid, 'emocions'::upcategory, now(), "
            "NULL, '\\x0000000178'::bytea, true)"
        ),
        {
            "id": str(up_id),
            "tid": str(up_ctx["tenant_id"]),
            "pid": str(up_ctx["profile_id"]),
            "uid": str(up_ctx["admin_id"]),
        },
    )
    # The CONSTRAINT TRIGGER fires when constraints are checked. Force it now.
    with pytest.raises(Exception) as exc:
        await db.execute(text("SET CONSTRAINTS ALL IMMEDIATE"))
    assert "up_crisi" in str(exc.value).lower() or "sidecar" in str(exc.value).lower()


# ── single-TX atomicity ──────────────────────────────────────────────────────


async def test_create_up_atomicity(up_ctx, monkeypatch):
    """Inject a DB failure at the outbox step → the whole create_up unit rolls back;
    ZERO rows in all 6 tables (UP, sidecar, feed, esfera, points, outbox).

    We wrap the call in an inner SAVEPOINT (begin_nested) so the rollback discards
    exactly what create_up wrote — the same boundary a real request gets when the
    router never reaches its commit() after the service raised."""
    db = up_ctx["db"]
    svc = UPService(db)
    pid = up_ctx["profile_id"]

    baseline = {
        t: await _count(db, t, profile_id=pid)
        for t in ("ups", "feed_entries", "esfera_radius", "points_ledger")
    }
    baseline_crisi_outbox = (
        await db.execute(
            text(
                "SELECT count(*) FROM outbox_events "
                "WHERE event_type = 'up.crisi.created' AND payload->>'profile_id' = :pid"
            ),
            {"pid": str(pid)},
        )
    ).scalar_one()

    async def _boom(*a, **k):
        raise RuntimeError("injected DB failure before outbox")

    monkeypatch.setattr(svc._outbox, "insert", _boom)

    sp = await db.begin_nested()  # inner SAVEPOINT around the unit of work
    with pytest.raises(RuntimeError):
        await svc.create_up(
            up_ctx["tenant_id"],
            pid,
            up_ctx["admin_id"],
            _req(
                category="emocions",
                is_crisi=True,
                note="atomic",
                crisi=CrisiData(trigger_text="x", duration_bucket="lt5"),
            ),
        )
    await sp.rollback()  # discard the partially-flushed unit (router never commits)

    # All 6 tables are back at baseline — nothing leaked.
    for t, n in baseline.items():
        assert await _count(db, t, profile_id=pid) == n, f"{t} leaked rows"
    after_crisi_outbox = (
        await db.execute(
            text(
                "SELECT count(*) FROM outbox_events "
                "WHERE event_type = 'up.crisi.created' AND payload->>'profile_id' = :pid"
            ),
            {"pid": str(pid)},
        )
    ).scalar_one()
    assert after_crisi_outbox == baseline_crisi_outbox
    # up_crisi sidecar also clean (count via JOIN to this profile's ups).
    sidecar_leak = (
        await db.execute(
            text(
                "SELECT count(*) FROM up_crisi c JOIN ups u ON u.id = c.up_id "
                "WHERE u.profile_id = :pid"
            ),
            {"pid": str(pid)},
        )
    ).scalar_one()
    assert sidecar_leak == 0


# ── KMS failure → 503, ZERO rows (prepare-before-persist) ────────────────────


async def test_kms_failure_no_rows(up_ctx, monkeypatch):
    """An Art-9 write whose encryption raises in the PREPARE phase writes NO rows
    (never plaintext-fallback) and propagates KmsUnavailableError (→ 503)."""
    db = up_ctx["db"]
    svc = UPService(db)

    import app.services.up_service as up_mod

    async def _kms_down(*a, **k):
        raise KmsUnavailableError("simulated KMS outage")

    # Fail the very first encrypt call (the note for an Art-9 category).
    monkeypatch.setattr(up_mod, "encrypt_field_for_tenant", _kms_down)

    before_ups = await _count(db, "ups", profile_id=up_ctx["profile_id"])
    before_feed = await _count(db, "feed_entries", profile_id=up_ctx["profile_id"])

    with pytest.raises(KmsUnavailableError):
        await svc.create_up(
            up_ctx["tenant_id"],
            up_ctx["profile_id"],
            up_ctx["admin_id"],
            _req(category="salut", note="blood test results"),
        )

    # PREPARE failed before any DB write → counts unchanged. No flush happened.
    assert await _count(db, "ups", profile_id=up_ctx["profile_id"]) == before_ups
    assert await _count(db, "feed_entries", profile_id=up_ctx["profile_id"]) == before_feed


# ── Art-9 never plaintext ─────────────────────────────────────────────────────


async def test_art9_never_plaintext(up_ctx):
    """A salut/emocions UP stores note_encrypted (NOT NULL) + note_plain NULL in raw
    DB; decrypting via the service round-trips the original plaintext."""
    db = up_ctx["db"]
    svc = UPService(db)
    secret = "Marc had a fever of 38.5 and we saw the pediatrician"
    result = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(category="salut", note=secret),
    )
    await db.flush()

    row = (
        await db.execute(
            text("SELECT note_plain, note_encrypted, note_search_tokens FROM ups WHERE id = :id"),
            {"id": str(result.id)},
        )
    ).first()
    assert row[0] is None  # note_plain NULL
    assert row[1] is not None and len(row[1]) > 0  # note_encrypted present
    assert secret.encode() not in row[1]  # ciphertext does not contain the plaintext
    assert len(row[2]) > 0  # search tokens populated for Art-9

    # The denormalised feed preview is ALSO encrypted (mirrors UP posture).
    feed = (
        await db.execute(
            text("SELECT preview_plain, preview_encrypted FROM feed_entries WHERE entity_id = :id"),
            {"id": str(result.id)},
        )
    ).first()
    assert feed[0] is None
    assert feed[1] is not None and len(feed[1]) > 0

    # Service decrypt round-trips.
    decrypted = await svc.get_up_decrypted(
        up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"]
    )
    assert decrypted["note"] == secret


async def test_non_art9_uses_plaintext(up_ctx):
    """A non-Art-9 ('casa') UP stores note_plain (NOT NULL) + note_encrypted NULL +
    empty search tokens (Option-H lower branch)."""
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(category="casa", note="built a lego tower"),
    )
    await db.flush()
    row = (
        await db.execute(
            text("SELECT note_plain, note_encrypted, note_search_tokens FROM ups WHERE id = :id"),
            {"id": str(result.id)},
        )
    ).first()
    assert row[0] == "built a lego tower"
    assert row[1] is None
    assert list(row[2]) == []


# ── points daily cap (TZ-aware) ───────────────────────────────────────────────


async def test_points_daily_cap(up_ctx):
    """The 6th UP in one tenant-local day awards 0 punts + daily_cap_reached=True."""
    db = up_ctx["db"]
    svc = UPService(db)
    results = []
    for _ in range(6):
        r = await svc.create_up(
            up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req()
        )
        await db.flush()
        results.append(r)

    assert [r.punts_awarded for r in results[:5]] == [5, 5, 5, 5, 5]
    assert results[5].punts_awarded == 0
    assert results[5].daily_cap_reached is True
    # 5th award is exactly the cap.
    assert results[4].daily_cap_reached is True


# ── pin idempotent ────────────────────────────────────────────────────────────


async def test_pin_idempotent(up_ctx):
    """Double pin → 200 {was_already:True}, NOT 409."""
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req()
    )
    await db.flush()

    # The result carries profile_id (Plan 020 cache-invalidation contract) alongside
    # the pin state; assert the pin-state subset (field-additive evolution).
    first = await svc.pin_memory(up_ctx["tenant_id"], result.id, up_ctx["admin_id"])
    assert (first["is_pinned"], first["was_already"]) == (True, False)
    second = await svc.pin_memory(up_ctx["tenant_id"], result.id, up_ctx["admin_id"])
    assert (second["is_pinned"], second["was_already"]) == (True, True)

    # unpin mirrors the idempotency.
    u1 = await svc.unpin_memory(up_ctx["tenant_id"], result.id, up_ctx["admin_id"])
    assert (u1["is_pinned"], u1["was_already"]) == (False, False)
    u2 = await svc.unpin_memory(up_ctx["tenant_id"], result.id, up_ctx["admin_id"])
    assert (u2["is_pinned"], u2["was_already"]) == (False, True)


# ── patch: is_crisi immutable + Art-9 transition ──────────────────────────────


async def test_patch_is_crisi_immutable(up_ctx):
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req()
    )
    await db.flush()
    with pytest.raises(IsCrisiImmutableError):
        await svc.patch_up(
            up_ctx["tenant_id"],
            result.id,
            up_ctx["admin_id"],
            UPPatchRequest(is_crisi=True),
        )


async def test_patch_category_art9_transition(up_ctx):
    """casa (plaintext) → salut (Art-9): the note is re-encrypted, note_plain becomes
    NULL, search tokens recomputed, and up.category_reclassified is audited."""
    db = up_ctx["db"]
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(category="casa", note="sensitive after all"),
    )
    await db.flush()

    # Pre-state: plaintext.
    pre = (
        await db.execute(
            text("SELECT note_plain, note_encrypted FROM ups WHERE id = :id"),
            {"id": str(result.id)},
        )
    ).first()
    assert pre[0] is not None and pre[1] is None

    await svc.patch_up(
        up_ctx["tenant_id"],
        result.id,
        up_ctx["admin_id"],
        UPPatchRequest(category="salut"),
    )
    await db.flush()

    post = (
        await db.execute(
            text(
                "SELECT note_plain, note_encrypted, note_search_tokens, category "
                "FROM ups WHERE id = :id"
            ),
            {"id": str(result.id)},
        )
    ).first()
    assert post[0] is None  # plain cleared
    assert post[1] is not None and len(post[1]) > 0  # now encrypted
    assert len(post[2]) > 0  # tokens recomputed
    assert post[3] == "salut"

    # Audit event for the reclassification.
    n = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up.category_reclassified' AND entity_id = :eid"
            ),
            {"eid": str(result.id)},
        )
    ).scalar_one()
    assert n == 1

    # The decrypted note still round-trips after the transition.
    dec = await svc.get_up_decrypted(up_ctx["tenant_id"], result.id, user_id=up_ctx["admin_id"])
    assert dec["note"] == "sensitive after all"


# ── consent gate (first real use) ─────────────────────────────────────────────


async def test_profile_creation_grants_ups_consent(family_ctx):
    """ProfileService records the first-use 'ups' consent when the responsible adult
    creates the profile, so a freshly onboarded family can log UPs."""
    from app.gdpr.consent import ConsentRepository

    live = await ConsentRepository(family_ctx["db"]).get_live(family_ctx["profile_id"], "ups")
    assert live is not None
    assert live.basis == "parental_authority"
    assert live.user_id == family_ctx["admin_id"]
    assert live.version


async def test_consent_required_for_up(family_ctx):
    """No live 'ups' consent → create_up raises 403 CONSENT_NOT_FOUND. Granting it
    then lets the same call succeed."""
    db = family_ctx["db"]
    svc = UPService(db)
    await revoke_ups_consent(
        db, family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    )

    with pytest.raises(ConsentNotFoundError):
        await svc.create_up(
            family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"], _req()
        )

    await grant_ups_consent(
        db, family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    )
    result = await svc.create_up(
        family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"], _req()
    )
    await db.flush()
    assert result.id is not None


# ── special-category access log on Art-9 read ─────────────────────────────────


async def test_special_category_log_on_crisi_read(up_ctx):
    """GET of an Art-9 (crisi) UP writes a special_category_access_log row; a
    non-Art-9 read does NOT."""
    db = up_ctx["db"]
    svc = UPService(db)

    crisi = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(
            category="emocions",
            is_crisi=True,
            crisi=CrisiData(trigger_text="loud party", duration_bucket="lt5"),
        ),
    )
    plain = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(category="casa", note="ordinary moment"),
    )
    await db.flush()

    before = await _count(db, "special_category_access_log", entity_id=crisi.id)
    await svc.get_up_decrypted(up_ctx["tenant_id"], crisi.id, user_id=up_ctx["admin_id"])
    await db.flush()
    after = await _count(db, "special_category_access_log", entity_id=crisi.id)
    assert after == before + 1

    # Non-Art-9 read writes nothing.
    await svc.get_up_decrypted(up_ctx["tenant_id"], plain.id, user_id=up_ctx["admin_id"])
    await db.flush()
    assert await _count(db, "special_category_access_log", entity_id=plain.id) == 0


# ── redact crisi (selective erasure) ──────────────────────────────────────────


async def test_redact_crisi_keeps_aggregates(up_ctx):
    """redact_crisi blanks the encrypted text + clears tokens + sets user_redacted_at
    while KEEPING duration_bucket / mood_after; audited as up_crisi.redacted."""
    db = up_ctx["db"]
    svc = UPService(db)
    crisi = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(
            category="emocions",
            is_crisi=True,
            crisi=CrisiData(
                trigger_text="x",
                resolution_text="y",
                duration_bucket="fifteen_to_30",
                mood_after="love",
            ),
        ),
    )
    await db.flush()

    await svc.redact_crisi(
        up_ctx["tenant_id"], crisi.id, up_ctx["admin_id"], reclassified_as="sensory_event"
    )
    await db.flush()

    row = (
        await db.execute(
            text(
                "SELECT trigger_text, resolution_text, search_tokens, user_redacted_at, "
                "duration_bucket, mood_after, reclassified_as FROM up_crisi WHERE up_id = :id"
            ),
            {"id": str(crisi.id)},
        )
    ).first()
    assert row[0] is None  # trigger blanked
    assert row[1] is None  # resolution blanked
    assert list(row[2]) == []  # tokens cleared
    assert row[3] is not None  # user_redacted_at set
    assert row[4] == "fifteen_to_30"  # aggregate KEPT
    assert row[5] == "love"  # aggregate KEPT
    assert row[6] == "sensory_event"  # reclassification recorded

    n = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE event_type = 'up_crisi.redacted' AND entity_id = :eid"
            ),
            {"eid": str(crisi.id)},
        )
    ).scalar_one()
    assert n == 1


async def test_redact_non_crisi_raises(up_ctx):
    db = up_ctx["db"]
    svc = UPService(db)
    plain = await svc.create_up(
        up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"], _req(category="casa")
    )
    await db.flush()
    with pytest.raises(NotACrisiError):
        await svc.redact_crisi(up_ctx["tenant_id"], plain.id, up_ctx["admin_id"])


# ── save_to_arxiu outbox sub-event (no cross-domain import) ────────────────────


async def test_save_to_arxiu_emits_outbox_event(up_ctx):
    """save_to_arxiu=true writes an up.saved_to_arxiu_requested outbox row in the
    same TX (Plan 023 drains it). No app.document import involved."""
    db = up_ctx["db"]
    upload_key = f"uploads/{uuid.uuid4()}.jpg"
    await db.execute(
        text(
            "INSERT INTO pending_uploads "
            "(id, tenant_id, profile_id, upload_key, context, mime, "
            "size_bytes_reserved, sha256_content_address, pipeline_status, expires_at) "
            "VALUES (:id, :tid, :pid, :key, 'up_document', 'image/jpeg', "
            "1024, :sha, 'pending', NULL)"
        ),
        {
            "id": str(uuid.uuid4()),
            "tid": str(up_ctx["tenant_id"]),
            "pid": str(up_ctx["profile_id"]),
            "key": upload_key,
            "sha": "a" * 64,
        },
    )
    svc = UPService(db)
    result = await svc.create_up(
        up_ctx["tenant_id"],
        up_ctx["profile_id"],
        up_ctx["admin_id"],
        _req(
            category="casa",
            save_to_arxiu=True,
            arxiu_section="escola",
            attachments=[{"upload_key": upload_key}],
        ),
    )
    await db.flush()

    rows = (
        await db.execute(
            text(
                "SELECT event_type, payload FROM outbox_events "
                "WHERE payload->>'up_id' = :uid ORDER BY event_type"
            ),
            {"uid": str(result.id)},
        )
    ).fetchall()
    types = {r[0] for r in rows}
    assert "up.created" in types
    assert "up.saved_to_arxiu_requested" in types
    sub = next(r for r in rows if r[0] == "up.saved_to_arxiu_requested")
    assert sub[1]["arxiu_section"] == "escola"
    assert "attachment_descriptor" not in sub[1]


@pytest.mark.parametrize("category", ["casa", "emocions"])
async def test_tag_is_encrypted_searchable_and_patchable(up_ctx, category):
    from app.services.feed_read_service import FeedReadService

    db = up_ctx["db"]
    tid, pid, uid = up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"]
    svc = UPService(db)
    result = await svc.create_up(tid, pid, uid, _req(category=category, tag="lectura-compartida"))
    detail = await svc.get_up_decrypted(tid, result.id, user_id=uid)
    assert detail["tag"] == "lectura-compartida"
    stored = (
        await db.execute(
            text("SELECT tag_encrypted, tag_search_tokens FROM ups WHERE id = :id"),
            {"id": result.id},
        )
    ).one()
    assert b"lectura" not in bytes(stored[0])
    assert stored[1]
    feed = FeedReadService(db)
    found = await feed.list_feed(tid, pid, user_id=uid, query="lectura")
    assert [item.entity_id for item in found.data] == [result.id]
    updated = await svc.patch_up(
        tid, result.id, uid, UPPatchRequest(category="esport", note="New note")
    )
    assert updated["tag"] == "lectura-compartida"
    found = await feed.list_feed(tid, pid, user_id=uid, query="lectura")
    assert [(item.entity_id, item.category) for item in found.data] == [(result.id, "esport")]
    await svc.patch_up(tid, result.id, uid, UPPatchRequest(tag="matemàtiques"))
    assert not (await feed.list_feed(tid, pid, user_id=uid, query="lectura")).data
    assert (await feed.list_feed(tid, pid, user_id=uid, query="matemàtiques")).data
    await svc.patch_up(tid, result.id, uid, UPPatchRequest(tag=None))
    assert not (await feed.list_feed(tid, pid, user_id=uid, query="matemàtiques")).data
    assert (await svc.get_up_decrypted(tid, result.id, user_id=uid))["tag"] is None


async def test_category_only_edit_updates_feed(up_ctx):
    from app.services.feed_read_service import FeedReadService

    tid, pid, uid = up_ctx["tenant_id"], up_ctx["profile_id"], up_ctx["admin_id"]
    svc = UPService(up_ctx["db"])
    result = await svc.create_up(tid, pid, uid, _req())
    await svc.patch_up(tid, result.id, uid, UPPatchRequest(category="escola"))
    feed = await FeedReadService(up_ctx["db"]).list_feed(tid, pid, user_id=uid)
    assert feed.data[0].category == "escola"


@pytest.mark.parametrize("tag", ["two words", "#tag", "--", "a" * 61])
def test_tag_rejects_invalid_words(tag):
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        _req(tag=tag)
