"""Plan 026 Step 15 — UP-delete → insight invalidation cascade VIA THE OUTBOX.

A deleted UP emits up.deleted; the outbox drainer's AI topic handler soft-deletes insights
citing it + flushes Redis + emits AI_INSIGHT_INVALIDATED. CRITICAL: app.ai must NOT import
app.up (the cascade is outbox-bridged) — that edge is asserted by lint-imports + the
import-linter contract; this test asserts the BEHAVIOUR.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import text

from app.ai.cascade import cascade_invalidate_for_up, cascade_restore_for_up
from app.ai.insight_service import InsightService
from app.tasks.outbox_drainer import _dispatch_one
from tests.factories.up import UPFactory
from tests.notifications.conftest import fetch_outbox_row, seed_outbox

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _relax_k_anon(monkeypatch):
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 1)


async def _seed_insight_citing_ups(family_ctx: dict) -> tuple[str, list[uuid.UUID]]:
    """Create an insight (stub pipeline) citing real UPs; return (insight_id, up_ids)."""
    db = family_ctx["db"]
    up_ids = []
    for _ in range(2):
        up = await UPFactory(
            db,
            tenant_id=family_ctx["tenant_id"],
            profile_id=family_ctx["profile_id"],
            author_user_id=family_ctx["admin_id"],
            category="casa",
        )
        up_ids.append(up.id)
    await db.flush()
    result = await InsightService(db).compute(
        family_ctx["tenant_id"],
        family_ctx["profile_id"],
        prompt_id="insight_family_weekly",
        prompt_version="v1",
    )
    assert result is not None
    return result["id"], up_ids


async def _set_deleted(db, up_id: uuid.UUID, *, deleted: bool) -> None:
    await db.execute(
        text("UPDATE ups SET deleted_at = CASE WHEN :d THEN now() END WHERE id = :id"),
        {"d": deleted, "id": str(up_id)},
    )


async def _insight_deleted_at(db, insight_id: str):
    return (
        await db.execute(text("SELECT deleted_at FROM insights WHERE id = :id"), {"id": insight_id})
    ).scalar_one()


async def test_cascade_invalidates_insight_directly(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """cascade_invalidate_for_up soft-deletes citing insights + emits AI_INSIGHT_INVALIDATED."""
    db = family_ctx["db"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)
    await _set_deleted(db, up_ids[0], deleted=True)

    n = await cascade_invalidate_for_up(db, tenant_id=family_ctx["tenant_id"], up_id=up_ids[0])
    assert n >= 1

    deleted_at = (
        await db.execute(text("SELECT deleted_at FROM insights WHERE id = :id"), {"id": insight_id})
    ).scalar_one()
    assert deleted_at is not None  # soft-deleted

    audit = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.insight.invalidated'"
            ),
            {"tid": str(family_ctx["tenant_id"])},
        )
    ).scalar_one()
    assert audit >= 1


async def test_up_delete_cascade_via_outbox(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """End-to-end: an up.deleted outbox row dispatched through the drainer invalidates the
    insight (the outbox bridge — no app.ai→app.up import)."""
    db = family_ctx["db"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)
    await _set_deleted(db, up_ids[0], deleted=True)

    event_id = await seed_outbox(
        db,
        tenant_id=family_ctx["tenant_id"],
        event_type="up.deleted",
        payload={
            "up_id": str(up_ids[0]),
            "profile_id": str(family_ctx["profile_id"]),
            "tenant_id": str(family_ctx["tenant_id"]),
        },
    )
    from app.core.redis import get_redis

    redis = get_redis()
    try:
        row = await fetch_outbox_row(db, event_id)
        outcome = await _dispatch_one(db, redis, row)
    finally:
        await redis.aclose()

    assert outcome == "processed"
    deleted_at = (
        await db.execute(text("SELECT deleted_at FROM insights WHERE id = :id"), {"id": insight_id})
    ).scalar_one()
    assert deleted_at is not None


async def test_invalidate_skips_a_up_that_is_live_again(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """A delete undone before its event drains leaves the insight alone."""
    db = family_ctx["db"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)

    n = await cascade_invalidate_for_up(db, tenant_id=family_ctx["tenant_id"], up_id=up_ids[0])

    assert n == 0
    assert await _insight_deleted_at(db, insight_id) is None


async def test_up_restore_brings_back_the_insight_via_outbox(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    db = family_ctx["db"]
    tid = family_ctx["tenant_id"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)
    await _set_deleted(db, up_ids[0], deleted=True)
    await cascade_invalidate_for_up(db, tenant_id=tid, up_id=up_ids[0])
    assert await _insight_deleted_at(db, insight_id) is not None

    await _set_deleted(db, up_ids[0], deleted=False)
    event_id = await seed_outbox(
        db,
        tenant_id=tid,
        event_type="up.restored",
        payload={
            "up_id": str(up_ids[0]),
            "profile_id": str(family_ctx["profile_id"]),
            "tenant_id": str(tid),
        },
    )
    from app.core.redis import get_redis

    redis = get_redis()
    try:
        outcome = await _dispatch_one(db, redis, await fetch_outbox_row(db, event_id))
    finally:
        await redis.aclose()

    assert outcome == "processed"
    assert await _insight_deleted_at(db, insight_id) is None
    audit = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events WHERE tenant_id = :tid "
                "AND event_type = 'ai.insight.restored' AND entity_id = :iid"
            ),
            {"tid": str(tid), "iid": insight_id},
        )
    ).scalar_one()
    assert audit == 1


async def test_restore_waits_until_every_cited_up_is_live(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    db = family_ctx["db"]
    tid = family_ctx["tenant_id"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)
    for up_id in up_ids:
        await _set_deleted(db, up_id, deleted=True)
    await cascade_invalidate_for_up(db, tenant_id=tid, up_id=up_ids[0])

    await _set_deleted(db, up_ids[0], deleted=False)
    assert await cascade_restore_for_up(db, tenant_id=tid, up_id=up_ids[0]) == 0
    assert await _insight_deleted_at(db, insight_id) is not None

    await _set_deleted(db, up_ids[1], deleted=False)
    assert await cascade_restore_for_up(db, tenant_id=tid, up_id=up_ids[1]) == 1
    assert await _insight_deleted_at(db, insight_id) is None
    # Idempotent: nothing left to bring back.
    assert await cascade_restore_for_up(db, tenant_id=tid, up_id=up_ids[1]) == 0


async def test_restore_leaves_an_insight_that_was_replaced(
    family_ctx: dict, ai_client_stub, redis_flush: None
) -> None:
    """A live insight with the same content hash already stands in its place."""
    db = family_ctx["db"]
    tid = family_ctx["tenant_id"]
    insight_id, up_ids = await _seed_insight_citing_ups(family_ctx)
    await _set_deleted(db, up_ids[0], deleted=True)
    await cascade_invalidate_for_up(db, tenant_id=tid, up_id=up_ids[0])
    await db.execute(
        text(
            "INSERT INTO insights (id, tenant_id, profile_id, kind, body_encrypted, "
            "confidence_score, model_version, prompt_version, prompt_id, state, insight_hash, "
            "confidence_band, disclaimer_required, generated_at) "
            "SELECT gen_random_uuid(), tenant_id, profile_id, kind, body_encrypted, "
            "confidence_score, model_version, prompt_version, prompt_id, state, insight_hash, "
            "confidence_band, disclaimer_required, now() FROM insights WHERE id = :id"
        ),
        {"id": insight_id},
    )

    await _set_deleted(db, up_ids[0], deleted=False)
    assert await cascade_restore_for_up(db, tenant_id=tid, up_id=up_ids[0]) == 0
    assert await _insight_deleted_at(db, insight_id) is not None


async def test_no_app_ai_to_app_up_import() -> None:
    """Domain isolation: the app.ai package must NOT import app.up / observation / document.

    AST-based (not substring) so prose mentioning 'app.up' in a docstring is not a false hit —
    only real `import`/`from` statements count. Mirrors the import-linter contract behaviourally.
    """
    import ast
    import pkgutil

    import app.ai as ai_pkg

    forbidden_roots = (
        "app.up",
        "app.observation",
        "app.document",
        "app.services.up_service",
        "app.repositories.up_repository",
        "app.models.up",
    )
    offenders: list[str] = []
    for mod_info in pkgutil.walk_packages(ai_pkg.__path__, prefix="app.ai."):
        spec = mod_info.module_finder.find_spec(mod_info.name)  # type: ignore[union-attr]
        if spec is None or spec.origin is None:
            continue
        with open(spec.origin, encoding="utf-8") as fh:
            tree = ast.parse(fh.read(), filename=spec.origin)
        for node in ast.walk(tree):
            names: list[str] = []
            if isinstance(node, ast.Import):
                names = [a.name for a in node.names]
            elif isinstance(node, ast.ImportFrom) and node.module:
                names = [node.module]
            for name in names:
                if any(name == r or name.startswith(r + ".") for r in forbidden_roots):
                    offenders.append(f"{mod_info.name}: imports {name}")
    assert not offenders, f"app.ai imports a forbidden domain: {offenders}"
