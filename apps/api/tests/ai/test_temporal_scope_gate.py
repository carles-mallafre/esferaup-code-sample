from __future__ import annotations

from datetime import UTC, datetime

import pytest
from fastapi import HTTPException

from app.api.routes.ai import _require_current_scope
from app.family.temporal_access import ProfileAccessScope, ProfileTemporalState

pytestmark = pytest.mark.no_database


def _scope(state: ProfileTemporalState, *, future: bool) -> ProfileAccessScope:
    return ProfileAccessScope(
        role="view_only",
        role_version=1,
        temporal_state=state,
        history_cutoff_at=datetime(2026, 8, 2, tzinfo=UTC),
        future_access_enabled=future,
        temporal_version=1,
        grant_id=None,
        header_snapshot_encrypted=None,
    )


def test_live_ai_rejects_history_only_scope_before_compute_or_dismiss() -> None:
    with pytest.raises(HTTPException) as exc_info:
        _require_current_scope(_scope(ProfileTemporalState.HISTORY_ONLY, future=False))

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail["error"]["code"] == "HISTORICAL_ACCESS_READ_ONLY"


def test_live_ai_accepts_current_future_scope() -> None:
    _require_current_scope(_scope(ProfileTemporalState.CURRENT, future=True))
