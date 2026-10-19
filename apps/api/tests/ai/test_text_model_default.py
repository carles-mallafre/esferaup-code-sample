"""The admin's default model drives every text use: Activa authoring, AI Patrons and OCR."""

from __future__ import annotations

import uuid
from types import SimpleNamespace

import pytest
from httpx import AsyncClient
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai import text_model
from app.ai.adapters.gemini_vertex import GeminiVertexAiClient
from app.config.settings import is_ga_model_id, settings
from app.ocr.adapters.gemini_vertex import GeminiVertexEngine
from tests.ai.conftest import grant_platform_staff
from tests.family.conftest import auth_headers, mint_access_token

pytestmark = pytest.mark.asyncio

CHOSEN = "gemini-3.5-flash"
CONFIG = "/api/v1/internal/admin/ai/config"


@pytest.fixture
def selectable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "gemini_model_name", "gemini-3.1-flash-lite")
    monkeypatch.setattr(settings, "gemini_selectable_models", [CHOSEN])


async def _staff_headers(family_ctx: dict, db: AsyncSession) -> dict[str, str]:
    await grant_platform_staff(db, family_ctx["admin_id"])
    token = await mint_access_token(family_ctx["admin_id"], family_ctx["tenant_id"], db)
    return auth_headers(token)


async def _save(client: AsyncClient, headers: dict, model: str):
    return await client.patch(
        CONFIG,
        headers={**headers, "Idempotency-Key": str(uuid.uuid4())},
        json={"default_model": model},
    )


class _FakeModels:
    def __init__(self, response: SimpleNamespace) -> None:
        self.response = response
        self.calls: list[dict] = []

    async def generate_content(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


@pytest.mark.no_database
@pytest.mark.usefixtures("selectable")
async def test_only_allowed_ga_models_are_honoured(monkeypatch: pytest.MonkeyPatch) -> None:
    assert text_model.effective_text_model(CHOSEN) == CHOSEN
    assert text_model.effective_text_model(None) == "gemini-3.1-flash-lite"
    assert text_model.effective_text_model("gemini-2.5-flash") == "gemini-3.1-flash-lite"

    preview = "gemini-3.9-flash-preview"
    monkeypatch.setattr(settings, "gemini_selectable_models", [CHOSEN, preview, "gemini-exp-1206"])
    assert not is_ga_model_id(preview)
    assert text_model.allowed_models() == ["gemini-3.1-flash-lite", CHOSEN]
    assert text_model.effective_text_model(preview) == "gemini-3.1-flash-lite"


@pytest.mark.no_database
@pytest.mark.usefixtures("selectable")
async def test_unreadable_default_falls_back_to_the_environment_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _boom(_db):
        raise OperationalError("SELECT", {}, Exception("database down"))

    monkeypatch.setattr(text_model, "_stored_default", _boom)

    assert await text_model.resolve_text_model() == "gemini-3.1-flash-lite"


@pytest.mark.usefixtures("selectable")
async def test_saved_default_is_what_patrons_and_ocr_resolve(
    test_client: AsyncClient, family_ctx: dict
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    assert await text_model.resolve_text_model(db) == "gemini-3.1-flash-lite"

    saved = await _save(test_client, headers, CHOSEN)
    assert saved.status_code == 200, saved.text

    assert await text_model.resolve_text_model(db) == CHOSEN
    health = (await test_client.get("/api/v1/internal/ai/model-health", headers=headers)).json()
    uses = {use["use"]: use for use in health["model_uses"]}
    for name in ("patrons", "ocr", "activa_text"):
        assert uses[name] == {
            "use": name,
            "model": CHOSEN,
            "location": settings.gemini_location,
            "follows_default": True,
        }
    assert uses["luma_comprehension"]["model"] == settings.luma_comprehension_model
    assert uses["luma_read_aloud"] == {
        "use": "luma_read_aloud",
        "model": settings.gemini_audio_model_name,
        "location": settings.gemini_audio_location,
        "follows_default": False,
    }
    assert uses["activa_illustrations"]["model"] == settings.image_model_name
    assert uses["activa_illustrations"]["location"] == settings.image_location
    assert not any(
        uses[name]["follows_default"]
        for name in ("luma_comprehension", "luma_read_aloud", "activa_illustrations")
    )


@pytest.mark.usefixtures("selectable")
async def test_a_preview_or_unknown_model_cannot_be_saved(
    test_client: AsyncClient, family_ctx: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    db = family_ctx["db"]
    headers = await _staff_headers(family_ctx, db)
    preview = "gemini-3.9-flash-preview"
    monkeypatch.setattr(settings, "gemini_selectable_models", [CHOSEN, preview])

    refused = await _save(test_client, headers, preview)
    assert refused.status_code == 422
    assert refused.json()["error"]["code"] == "MODEL_NOT_GA"
    experimental = await _save(test_client, headers, "gemini-exp-1206")
    assert experimental.json()["error"]["code"] == "MODEL_NOT_GA"
    unknown = await _save(test_client, headers, "gemini-9-ultra")
    assert unknown.status_code == 422
    assert unknown.json()["error"]["code"] == "UNKNOWN_MODEL"

    config = (await test_client.get(CONFIG, headers=headers)).json()
    assert preview not in config["available_models"]
    assert await text_model.resolve_text_model(db) == "gemini-3.1-flash-lite"


@pytest.mark.no_database
@pytest.mark.usefixtures("selectable")
async def test_patrons_and_ocr_adapters_call_the_saved_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def _stored(_db):
        return CHOSEN

    monkeypatch.setattr(text_model, "_stored_default", _stored)
    insight_models = _FakeModels(
        SimpleNamespace(
            parsed={"title_ca": "t", "source_up_ids": []}, text=None, model_version=None
        )
    )
    ocr_models = _FakeModels(
        SimpleNamespace(parsed={"text": "Certificat", "confidence": 0.9}, text=None)
    )
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex._get_vertex_client",
        lambda _location: SimpleNamespace(aio=SimpleNamespace(models=insight_models)),
    )
    monkeypatch.setattr(
        "app.ocr.adapters.gemini_vertex._get_vertex_client",
        lambda _location: SimpleNamespace(aio=SimpleNamespace(models=ocr_models)),
    )
    monkeypatch.setattr("app.ai.client._client_instance", GeminiVertexAiClient())

    insight = await GeminiVertexAiClient().generate_insight(
        prompt_id="insight.weekly",
        prompt_version="1",
        user_payload={"system_prompt": "s", "user_message": "m", "source_up_ids": []},
        response_schema={"type": "object", "properties": {}},
    )
    ocr = await GeminiVertexEngine().extract(b"%PDF-1.7", "application/pdf")

    assert insight_models.calls[0]["model"] == CHOSEN
    assert insight["model_id"] == insight["model_version"] == CHOSEN
    assert ocr_models.calls[0]["model"] == CHOSEN
    assert ocr.model_id == ocr.model_version == CHOSEN
    # 3.x models take a thinking level, not the 2.x budget.
    for call in (insight_models.calls[0], ocr_models.calls[0]):
        assert call["config"].thinking_config.thinking_level is not None
        assert call["config"].thinking_config.thinking_budget is None
