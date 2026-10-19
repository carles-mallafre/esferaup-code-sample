from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.services.ai_governance_service import AiGovernanceService, allowed_models


@pytest.fixture
def models(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import ai_governance_service

    monkeypatch.setattr(
        ai_governance_service.settings, "gemini_model_name", "gemini-3.1-flash-lite"
    )
    monkeypatch.setattr(
        ai_governance_service.settings,
        "gemini_selectable_models",
        ["gemini-3.5-flash", "gemini-3.1-flash-lite"],
    )
    monkeypatch.setattr(ai_governance_service.settings, "kill_ai_global", False)


def _cfg(default_model: str) -> SimpleNamespace:
    return SimpleNamespace(enabled=True, default_model=default_model)


def _policy(model: str | None) -> SimpleNamespace:
    return SimpleNamespace(enabled=None, model=model, tier="standard")


@pytest.mark.no_database
@pytest.mark.usefixtures("models")
def test_allowed_models_lead_with_the_configured_default_without_duplicates() -> None:
    assert allowed_models() == ["gemini-3.1-flash-lite", "gemini-3.5-flash"]


@pytest.mark.no_database
@pytest.mark.usefixtures("models")
def test_retired_stored_models_fall_back_to_the_configured_default() -> None:
    service = AiGovernanceService(db=None)  # type: ignore[arg-type]

    assert (
        service.resolve(_cfg("gemini-2.5-flash"), None, kill_active=False).model
        == "gemini-3.1-flash-lite"
    )
    assert (
        service.resolve(
            _cfg("gemini-3.5-flash"), _policy("gemini-2.5-flash"), kill_active=False
        ).model
        == "gemini-3.5-flash"
    )
    assert AiGovernanceService.default_model(_cfg("gemini-2.5-flash")) == "gemini-3.1-flash-lite"


@pytest.mark.no_database
@pytest.mark.usefixtures("models")
def test_allowed_stored_models_are_kept() -> None:
    service = AiGovernanceService(db=None)  # type: ignore[arg-type]

    assert (
        service.resolve(
            _cfg("gemini-3.1-flash-lite"), _policy("gemini-3.5-flash"), kill_active=False
        ).model
        == "gemini-3.5-flash"
    )
