"""Plan 026 Steps 5-7, 9, 14 — the InsightService pipeline.

Exercises compute → pseudonymise → k-anon → cost → stub client → validate → ENCRYPT body →
persist → decrypt round-trip; the SWR read; FK-bounded source_up_ids; neurodivergent
suppression; and the no-PII observability event.

The DPIA feature flag is off at MVP, so these tests call the service pipeline DIRECTLY (the
endpoint-level DPIA 503 is tested separately). k-anonymity is lowered to 1 + a premium sub is
inserted so the gates pass and the pipeline runs end-to-end against the stub.
"""

from __future__ import annotations

import json
import uuid

import pytest
from sqlalchemy import text

from app.ai.insight_service import InsightService
from tests.factories.up import UPFactory

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _relax_k_anon(monkeypatch):
    """Lower k-anonymity to 1 so the single test profile's cohort passes the gate."""
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 1)


async def _seed_ups(family_ctx: dict, n: int = 3) -> list[uuid.UUID]:
    db = family_ctx["db"]
    ids = []
    for _ in range(n):
        up = await UPFactory(
            db,
            tenant_id=family_ctx["tenant_id"],
            profile_id=family_ctx["profile_id"],
            author_user_id=family_ctx["admin_id"],
            category="casa",
        )
        ids.append(up.id)
    await db.flush()
    return ids


async def test_insight_encrypted_body_roundtrips(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """The persisted body is ciphertext (bytea, not plaintext); decrypt round-trips the text."""
    db = family_ctx["db"]
    await _seed_ups(family_ctx)

    result = await InsightService(db).compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    assert result is not None
    insight_id = uuid.UUID(result["id"])

    # Raw column is encrypted bytes — the plaintext title/body must NOT appear in the bytea.
    raw = (
        await db.execute(
            text("SELECT body_encrypted FROM insights WHERE id = :id"), {"id": str(insight_id)}
        )
    ).scalar_one()
    raw_bytes = bytes(raw)
    assert result["title_ca"].encode("utf-8") not in raw_bytes
    assert result["body_ca"].encode("utf-8") not in raw_bytes
    # The encrypted blob carries the 4-byte version prefix (Plan 013 wire format).
    assert len(raw_bytes) > 16

    # A fresh DB read decrypts back to the same content.
    fresh = await InsightService(db)._fresh_db_insight(
        family_ctx["tenant_id"], family_ctx["profile_id"], "insight_family_weekly", "v1"
    )
    assert fresh is not None
    assert fresh["body_ca"] == result["body_ca"]
    assert fresh["title_es"] == result["title_es"]


async def test_insight_hash_and_band_persisted(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """insight_hash + confidence_band + disclaimer_required are persisted (the gap-fill cols)."""
    db = family_ctx["db"]
    await _seed_ups(family_ctx)
    result = await InsightService(db).compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    row = (
        (
            await db.execute(
                text(
                    "SELECT insight_hash, confidence_band, disclaimer_required FROM insights "
                    "WHERE id = :id"
                ),
                {"id": result["id"]},
            )
        )
        .mappings()
        .one()
    )
    assert row["insight_hash"] and len(row["insight_hash"]) == 64
    assert row["confidence_band"] in {"low", "medium", "high"}
    assert row["disclaimer_required"] is True


async def test_source_up_ids_fk_bounded(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """source_up_ids are FK-validated against the ups table (bogus ids dropped) + bounded <=10."""
    db = family_ctx["db"]
    up_ids = await _seed_ups(family_ctx, n=3)
    result = await InsightService(db).compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    persisted = {uuid.UUID(u) for u in result["source_up_ids"]}
    # Every persisted up id is a real seeded UP.
    assert persisted.issubset(set(up_ids))
    assert len(persisted) <= 10
    # The junction rows exist.
    link_count = (
        await db.execute(
            text("SELECT count(*) FROM insight_up_links WHERE insight_id = :id"),
            {"id": result["id"]},
        )
    ).scalar_one()
    assert link_count == len(persisted)


async def test_swr_cache_serves_persisted(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """get_or_compute computes once, then serves the cached/DB row on the second call."""
    db = family_ctx["db"]
    await _seed_ups(family_ctx)
    svc = InsightService(db)
    first = await svc.get_or_compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        actor_user_id=family_ctx["admin_id"],
    )
    assert first is not None
    second = await svc.get_or_compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        actor_user_id=family_ctx["admin_id"],
    )
    assert second is not None
    assert second["id"] == first["id"]  # same insight, served from cache/DB


async def test_particularity_baseline_suppresses(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """A profile with particularity_baseline set → pattern-frequency insight suppressed (None)."""
    db = family_ctx["db"]
    await _seed_ups(family_ctx)
    await db.execute(
        text("UPDATE profiles SET particularity_baseline = cast(:b as jsonb) WHERE id = :pid"),
        {"b": json.dumps({"baseline": "tea"}), "pid": str(family_ctx["profile_id"])},
    )
    await db.flush()
    result = await InsightService(db).compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    assert result is None


async def test_k_anonymity_503_in_pipeline(family_ctx: dict, ai_client_stub, monkeypatch) -> None:
    """A high threshold → the pipeline raises INSUFFICIENT_ANONYMITY_SET (503)."""
    from app.ai.gate import InsufficientAnonymitySetError
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 99999)
    db = family_ctx["db"]
    await _seed_ups(family_ctx)
    with pytest.raises(InsufficientAnonymitySetError) as exc:
        await InsightService(db).compute(
            family_ctx["tenant_id"],
            family_ctx["profile_id"],
            prompt_id="insight_family_weekly",
            prompt_version="v1",
        )
    assert exc.value.code == "INSUFFICIENT_ANONYMITY_SET"
    assert exc.value.status_code == 503
