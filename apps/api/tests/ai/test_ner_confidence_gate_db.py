from __future__ import annotations

import pytest
from sqlalchemy import text

from app.ai.insight_service import InsightService

pytestmark = pytest.mark.asyncio


async def test_low_confidence_skip_persists_only_aggregate_forensic_metadata(
    family_ctx: dict,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    db = family_ctx["db"]
    monkeypatch.setattr("sentry_sdk.capture_message", lambda *args, **kwargs: None)

    await InsightService(db)._record_low_confidence_skip(
        confidence=0.82,
        artifact_manifest_version="ner-pseudonymisation-2026-08-09.v1",
    )

    row = (
        (
            await db.execute(
                text(
                    "SELECT user_id, entity_type, entity_id, ip_hash, user_agent_hash, payload "
                    "FROM audit_events WHERE tenant_id IS NULL "
                    "AND event_type = 'ai.anonymization.low_confidence_skipped' "
                    "ORDER BY occurred_at DESC LIMIT 1"
                ),
            )
        )
        .mappings()
        .one()
    )
    assert row["user_id"] is None
    assert row["entity_type"] is None
    assert row["entity_id"] is None
    assert row["ip_hash"] is None
    assert row["user_agent_hash"] is None
    payload = dict(row["payload"])
    assert "tenant_id" not in payload
    assert payload["locale"] == "ca"
    assert payload["confidence_band"] == "below_0_85"
    assert payload["decision"] == "skipped"
    serialized = str(payload)
    assert str(family_ctx["profile_id"]) not in serialized
    assert str(family_ctx["admin_id"]) not in serialized
    assert not any(key in payload for key in ("source_up_ids", "text", "ip", "user_agent"))


async def test_0154_seeds_exact_audit_kind(family_ctx: dict) -> None:
    db = family_ctx["db"]
    count = (
        await db.execute(
            text(
                "SELECT count(*) FROM audit_event_kinds "
                "WHERE kind = 'ai.anonymization.low_confidence_skipped'"
            )
        )
    ).scalar_one()
    assert count == 1
