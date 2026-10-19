"""Real-Postgres coverage for the always-on deterministic Patró path."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.heuristics.pattern_v1 import PatternInput, build_pattern_candidate
from app.ai.pattern_service import PatternService
from app.tasks.ai_tasks import _precompute_profiles
from tests.family.conftest import (
    auth_headers,
    bind_request_identity,
    mint_access_token,
)

pytestmark = pytest.mark.asyncio

_AS_OF = date(2026, 8, 9)


def _pattern_inputs(*, factor_category: str = "esport") -> list[PatternInput]:
    week_start = datetime(2026, 6, 30, 12, tzinfo=UTC)
    entries: list[PatternInput] = []
    for week in range(6):
        entries.extend(
            [
                PatternInput(uuid.uuid4(), factor_category, week_start + timedelta(weeks=week)),
                PatternInput(
                    uuid.uuid4(),
                    factor_category,
                    week_start + timedelta(weeks=week, days=1),
                ),
            ]
        )
        if week % 2 == 0:
            entries.append(
                PatternInput(
                    uuid.uuid4(),
                    "casa",
                    week_start + timedelta(weeks=week, days=2),
                )
            )
    return entries


async def _insert_inputs(
    db: AsyncSession,
    family_ctx: dict,
    *,
    factor_category: str = "esport",
) -> list[uuid.UUID]:
    entries = _pattern_inputs(factor_category=factor_category)
    for entry in entries:
        note = "A deliberately long supporting note " + ("x" * 150)
        note_plain: str | None = note
        note_encrypted: bytes | None = None
        if entry.category in {"salut", "emocions"}:
            from app.encryption import encrypt_field_for_tenant

            note_encrypted = await encrypt_field_for_tenant(
                plaintext=note.encode("utf-8"),
                tenant_id=family_ctx["tenant_id"],
                column_key="UP.note",
                row_id=entry.entity_id,
                db=db,
            )
            note_plain = None
        await db.execute(
            text(
                "INSERT INTO ups (id, tenant_id, profile_id, author_user_id, category, "
                "occurred_at, occurred_at_tz, note_plain, note_encrypted, note_search_tokens, "
                "attachments) "
                "VALUES (:id, :tid, :pid, :uid, CAST(:category AS upcategory), :occurred_at, "
                "'UTC', :note_plain, :note_encrypted, '{}', '[]'::jsonb)"
            ),
            {
                "id": str(entry.entity_id),
                "tid": str(family_ctx["tenant_id"]),
                "pid": str(family_ctx["profile_id"]),
                "uid": str(family_ctx["admin_id"]),
                "category": entry.category,
                "occurred_at": entry.occurred_at,
                "note_plain": note_plain,
                "note_encrypted": note_encrypted,
            },
        )
    await db.flush()
    return [entry.entity_id for entry in entries]


async def test_pattern_v1_is_deterministic_and_bounded() -> None:
    entries = _pattern_inputs()
    first = build_pattern_candidate(entries, as_of=_AS_OF)
    second = build_pattern_candidate(list(reversed(entries)), as_of=_AS_OF)

    assert first is not None
    assert second is not None
    assert first == second
    assert first.factor_key == "esport"
    assert len(first.paired_series) == 6
    assert len(first.supporting_entries) == 10
    assert 0 <= first.confidence <= 1
    assert "Sembla" in first.statement_ca
    assert "Parece" in first.statement_es
    assert "may" in first.statement_en


async def test_service_and_task_replays_do_not_duplicate_patterns(
    db_session: AsyncSession,
    family_ctx: dict,
) -> None:
    await _insert_inputs(db_session, family_ctx)
    service = PatternService(db_session)

    first = await service.generate_profile(
        family_ctx["tenant_id"], family_ctx["profile_id"], as_of=_AS_OF
    )
    second = await service.generate_profile(
        family_ctx["tenant_id"], family_ctx["profile_id"], as_of=_AS_OF
    )
    assert first["changed"] is True
    assert second["changed"] is False
    assert first["pattern_id"] == second["pattern_id"]

    count = (
        await db_session.execute(
            text(
                "SELECT count(*) FROM patterns WHERE tenant_id = :tid AND profile_id = :pid "
                "AND heuristic_version = 'pattern_v1' AND deleted_at IS NULL"
            ),
            {"tid": str(family_ctx["tenant_id"]), "pid": str(family_ctx["profile_id"])},
        )
    ).scalar_one()
    assert count == 1

    from app.core.tenant_context import system_context

    with system_context():
        task_first = await _precompute_profiles(db_session, as_of=_AS_OF)
        task_second = await _precompute_profiles(db_session, as_of=_AS_OF)
    assert task_first["failed"] == 0
    assert task_second["failed"] == 0
    assert task_second["changed"] == 0


async def test_weekly_worker_refreshes_new_inputs_without_provider_ai(
    family_ctx, redis_flush, monkeypatch
):
    from app.config.settings import settings
    from app.tasks import ai_tasks
    from tests.security.worker_login import worker_system_sessions

    db = family_ctx["db"]
    await _insert_inputs(db, family_ctx)
    monkeypatch.setattr(settings, "feature_ai_enabled", False)
    monkeypatch.setattr("app.db.session.make_system_session", worker_system_sessions(db))
    run_at = datetime(2026, 8, 9, 1, tzinfo=UTC)

    class Clock:
        @staticmethod
        def now(tz):
            return run_at.astimezone(tz)

    monkeypatch.setattr(ai_tasks, "datetime", Clock)

    async def current_pattern():
        return (
            await db.execute(
                text(
                    "SELECT id, generation_fingerprint, supporting_entries FROM patterns "
                    "WHERE tenant_id = :tid AND profile_id = :pid AND deleted_at IS NULL"
                ),
                {"tid": family_ctx["tenant_id"], "pid": family_ctx["profile_id"]},
            )
        ).one()

    first = await ai_tasks._run()
    assert first["status"] == "completed"
    assert first["ai_branch"] == "disabled"
    assert first["heuristic"]["failed"] == 0
    assert first["heuristic"]["changed"] == 1
    original = await current_pattern()
    assert (await ai_tasks._run())["heuristic"]["changed"] == 0

    new_up_id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO ups (id, tenant_id, profile_id, author_user_id, category, "
            "occurred_at, note_plain) VALUES (:id, :tid, :pid, :uid, 'esport', "
            "'2026-08-12T12:00:00Z', 'QA weekly input')"
        ),
        {
            "id": new_up_id,
            "tid": family_ctx["tenant_id"],
            "pid": family_ctx["profile_id"],
            "uid": family_ctx["admin_id"],
        },
    )
    await db.commit()
    run_at += timedelta(weeks=1)
    refreshed = await ai_tasks._run()
    assert refreshed["heuristic"]["changed"] == 1
    assert refreshed["heuristic"]["failed"] == 0
    assert refreshed["ai_branch"] == "disabled"
    current = await current_pattern()
    assert current.id == original.id
    assert current.generation_fingerprint != original.generation_fingerprint
    assert str(new_up_id) in {entry["entity_id"] for entry in current.supporting_entries}
    assert (await ai_tasks._run())["heuristic"]["changed"] == 0


async def test_weekly_worker_busts_the_cached_home_of_a_changed_profile(
    family_ctx, redis_flush, monkeypatch
):
    """Inici's pattern advice rides in the cached home payload: a new Patró must
    not wait out the SWR window (pull-to-refresh showed the stale payload)."""
    from app.config.settings import settings
    from app.core.redis import get_redis
    from app.services.home_cache import home_payload_key, home_payload_registry_key
    from app.tasks import ai_tasks
    from tests.security.worker_login import worker_system_sessions

    db = family_ctx["db"]
    await _insert_inputs(db, family_ctx)
    monkeypatch.setattr(settings, "feature_ai_enabled", False)
    monkeypatch.setattr("app.db.session.make_system_session", worker_system_sessions(db))
    run_at = datetime(2026, 8, 9, 1, tzinfo=UTC)

    class Clock:
        @staticmethod
        def now(tz):
            return run_at.astimezone(tz)

    monkeypatch.setattr(ai_tasks, "datetime", Clock)

    profile_id = family_ctx["profile_id"]
    cached_key = home_payload_key(profile_id, family_ctx["admin_id"])
    redis = get_redis()

    async def cache_home() -> None:
        await redis.setex(cached_key, 30, "{}")
        await redis.sadd(home_payload_registry_key(profile_id), cached_key)

    try:
        await cache_home()
        first = await ai_tasks._run()
        assert first["heuristic"]["changed"] == 1
        assert await redis.exists(cached_key) == 0

        await cache_home()
        unchanged = await ai_tasks._run()
        assert unchanged["heuristic"]["changed"] == 0
        assert await redis.exists(cached_key) == 1
    finally:
        await redis.aclose()


async def test_list_detail_mute_are_always_on_bounded_and_tenant_scoped(
    test_client: AsyncClient,
    family_ctx: dict,
    other_family: dict,
) -> None:
    db = family_ctx["db"]
    from app.config.settings import settings

    assert settings.feature_ai_enabled is False
    await _insert_inputs(db, family_ctx, factor_category="emocions")
    outcome = await PatternService(db).generate_profile(
        family_ctx["tenant_id"], family_ctx["profile_id"], as_of=_AS_OF
    )
    pattern_id = outcome["pattern_id"]
    assert pattern_id is not None

    family_token = await mint_access_token(family_ctx["admin_id"], family_ctx["tenant_id"], db)
    family_headers = auth_headers(family_token)

    response = await test_client.get(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons",
        headers=family_headers,
    )
    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == [str(pattern_id)]

    detail = await test_client.get(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons/{pattern_id}",
        headers=family_headers,
    )
    assert detail.status_code == 200
    payload = detail.json()
    assert payload["factor_key"] == "emocions"
    assert len(payload["paired_series"]) == 6
    assert len(payload["supporting_entries"]) == 10
    assert all(len(row["note_excerpt"]) <= 120 for row in payload["supporting_entries"])
    special_access_count = (
        await db.execute(
            text(
                "SELECT count(*) FROM special_category_access_log "
                "WHERE tenant_id = :tid AND user_id = :uid AND entity_type = 'up'"
            ),
            {"tid": str(family_ctx["tenant_id"]), "uid": str(family_ctx["admin_id"])},
        )
    ).scalar_one()
    assert special_access_count == 10

    first_headers = {**family_headers, "Idempotency-Key": str(uuid.uuid4())}
    muted = await test_client.patch(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons/{pattern_id}/mute",
        headers=first_headers,
        json={"muted": True},
    )
    assert muted.status_code == 200
    assert muted.json() == {"id": str(pattern_id), "muted": True}

    second_headers = {**family_headers, "Idempotency-Key": str(uuid.uuid4())}
    replay = await test_client.patch(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons/{pattern_id}/mute",
        headers=second_headers,
        json={"muted": True},
    )
    assert replay.status_code == 200
    assert replay.json() == muted.json()

    empty = await test_client.get(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons",
        headers=family_headers,
    )
    assert empty.status_code == 200
    assert empty.json() == []

    audit_count = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_events "
                "WHERE tenant_id = :tid AND event_type = 'pattern.muted' "
                "AND entity_id = :pattern_id"
            ),
            {"tid": str(family_ctx["tenant_id"]), "pattern_id": str(pattern_id)},
        )
    ).scalar_one()
    outbox_count = (
        await db.execute(
            text(
                "SELECT count(*) FROM outbox_events "
                "WHERE tenant_id = :tid AND event_type = 'pattern.muted'"
            ),
            {"tid": str(family_ctx["tenant_id"])},
        )
    ).scalar_one()
    assert audit_count == 1
    assert outbox_count == 1

    await bind_request_identity(
        db,
        other_family["tenant_id"],
        other_family["admin_id"],
        role="admin",
    )
    other_token = await mint_access_token(other_family["admin_id"], other_family["tenant_id"], db)
    cross_tenant = await test_client.get(
        f"/api/v1/profiles/{family_ctx['profile_id']}/patrons/{pattern_id}",
        headers=auth_headers(other_token),
    )
    assert cross_tenant.status_code == 404
