from __future__ import annotations

from unittest.mock import AsyncMock, Mock

import pytest

from app.ai.insight_service import InsightService

pytestmark = pytest.mark.no_database


@pytest.mark.asyncio
async def test_low_confidence_telemetry_contains_no_child_source_or_network_identifiers(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    db = AsyncMock()
    audit = AsyncMock()
    service = InsightService(db)
    service._audit = audit
    capture = Mock()
    monkeypatch.setattr("sentry_sdk.capture_message", capture)

    await service._record_low_confidence_skip(
        confidence=0.81,
        artifact_manifest_version="ner-pseudonymisation-2026-08-09.v1",
    )

    audit.append.assert_not_awaited()
    audit.append_ai_ner_low_confidence_skip.assert_awaited_once_with(
        confidence_band="below_0_85",
        artifact_manifest_version="ner-pseudonymisation-2026-08-09.v1",
    )
    capture.assert_called_once()
