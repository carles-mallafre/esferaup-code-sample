from __future__ import annotations

import json
import uuid
from types import SimpleNamespace
from typing import Any

import pytest

from app.ai.adapters.gemini_api import GeminiApiError
from app.ai.adapters.gemini_vertex import GeminiVertexAiClient


class _FakeModels:
    def __init__(self, response: object) -> None:
        self.response = response
        self.calls: list[dict[str, Any]] = []

    async def generate_content(self, **kwargs: Any) -> object:
        self.calls.append(kwargs)
        return self.response

    async def get(self, **kwargs: Any) -> object:
        self.calls.append(kwargs)
        return SimpleNamespace(name=kwargs["model"])


def _client_with_response(response: object) -> tuple[object, _FakeModels]:
    models = _FakeModels(response)
    return SimpleNamespace(aio=SimpleNamespace(models=models)), models


@pytest.mark.asyncio
async def test_vertex_adapter_requests_structured_json_and_sets_server_provenance(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source_id = "00000000-0000-0000-0000-000000000001"
    source_alias = "UP-requestnonce-1"
    response = SimpleNamespace(
        parsed={
            "kind": "plan_recommendation",
            "title_ca": "Possible tendència",
            "title_es": "Posible tendencia",
            "body_ca": "Podria ser útil observar-ho.",
            "body_es": "Podría ser útil observarlo.",
            "source_up_ids": [source_alias],
            "confidence_band": "low",
            "disclaimer_required": True,
            "prompt_id": "model-controlled",
        },
        model_version="gemini-3.1-flash-lite-20260507",
        text=None,
    )
    fake_client, models = _client_with_response(response)
    locations: list[str] = []

    def _client(location: str) -> object:
        locations.append(location)
        return fake_client

    monkeypatch.setattr("app.ai.adapters.gemini_vertex._get_vertex_client", _client)
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex.settings.gemini_model_name", "gemini-3.1-flash-lite"
    )
    monkeypatch.setattr("app.ai.adapters.gemini_vertex.settings.gemini_location", "eu")
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex.secrets.token_urlsafe", lambda _size: "requestnonce"
    )

    result = await GeminiVertexAiClient().generate_insight(
        prompt_id="insight_family_weekly",
        prompt_version="2026-07-18",
        user_payload={
            "system_prompt": "Return a careful hypothetical insight.",
            "user_message": "Summarise the pseudonymised week.",
            "source_up_ids": [source_id],
        },
        response_schema={"type": "object", "properties": {}},
    )

    assert result["prompt_id"] == "insight_family_weekly"
    assert result["prompt_version"] == "2026-07-18"
    assert result["model_id"] == "gemini-3.1-flash-lite"
    assert result["model_version"] == "gemini-3.1-flash-lite-20260507"
    assert result["source_up_ids"] == [source_id]
    assert len(models.calls) == 1
    call = models.calls[0]
    assert call["model"] == "gemini-3.1-flash-lite"
    assert locations == ["eu"]
    assert "Allowed evidence aliases" in call["contents"]
    assert source_alias in call["contents"]
    assert source_id not in call["contents"]
    assert call["config"].response_mime_type == "application/json"
    provider_schema = call["config"].response_json_schema
    assert provider_schema["properties"]["source_up_ids"]["items"]["enum"] == [source_alias]
    assert source_id not in json.dumps(provider_schema)
    assert call["config"].thinking_config.thinking_level == "MINIMAL"
    assert call["config"].thinking_config.thinking_budget is None


@pytest.mark.asyncio
async def test_vertex_adapter_parses_text_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    body = {"kind": "outburst_tip", "confidence_band": "low"}
    fake_client, _ = _client_with_response(
        SimpleNamespace(parsed=None, text=json.dumps(body), model_version=None)
    )
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex._get_vertex_client", lambda _location: fake_client
    )

    result = await GeminiVertexAiClient().generate_insight(
        prompt_id="insight_outburst_tip",
        prompt_version="v1",
        user_payload={"system_prompt": "safe", "user_message": "summary"},
        response_schema={"type": "object"},
    )

    assert result["kind"] == "outburst_tip"
    assert result["model_version"]


@pytest.mark.asyncio
async def test_vertex_adapter_rejects_tenant_id_before_network(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    called = False

    def _unexpected_client(_location: str) -> object:
        nonlocal called
        called = True
        return object()

    monkeypatch.setattr("app.ai.adapters.gemini_vertex._get_vertex_client", _unexpected_client)

    with pytest.raises(ValueError, match="tenant_id"):
        await GeminiVertexAiClient().generate_insight(
            prompt_id="insight_family_weekly",
            prompt_version="v1",
            user_payload={
                "tenant_id": "forbidden",
                "system_prompt": "safe",
                "user_message": "summary",
            },
            response_schema={"type": "object"},
        )
    assert called is False


@pytest.mark.asyncio
async def test_vertex_adapter_rejects_nested_profile_id_before_network(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    called = False

    def _unexpected_client(_location: str) -> object:
        nonlocal called
        called = True
        return object()

    monkeypatch.setattr("app.ai.adapters.gemini_vertex._get_vertex_client", _unexpected_client)
    with pytest.raises(ValueError, match="profile_id"):
        await GeminiVertexAiClient().generate_insight(
            prompt_id="insight_family_weekly",
            prompt_version="v1",
            user_payload={
                "system_prompt": "safe",
                "user_message": "summary",
                "meta": {"profile_id": str(uuid.uuid4())},
            },
            response_schema={"type": "object"},
        )
    assert called is False


@pytest.mark.asyncio
async def test_vertex_adapter_rejects_unknown_evidence_alias(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_client, _ = _client_with_response(
        SimpleNamespace(
            parsed={"source_up_ids": ["UP-hallucinated-1"]}, text=None, model_version=None
        )
    )
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex._get_vertex_client", lambda _location: fake_client
    )
    with pytest.raises(GeminiApiError, match="unknown evidence alias"):
        await GeminiVertexAiClient().generate_insight(
            prompt_id="insight_family_weekly",
            prompt_version="v1",
            user_payload={
                "system_prompt": "safe",
                "user_message": "summary",
                "source_up_ids": [str(uuid.uuid4())],
            },
            response_schema={"type": "object"},
        )


@pytest.mark.asyncio
async def test_non_vertex_provider_never_enables_external_generation(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ai.adapters import gemini_api

    monkeypatch.setattr(gemini_api.settings, "ai_provider", "stub")
    assert gemini_api.is_available() is False
    with pytest.raises(GeminiApiError, match="gemini_vertex"):
        await gemini_api.generate_text("safe", model="gemini-2.5-flash")


@pytest.mark.asyncio
async def test_activa_vertex_failure_does_not_echo_provider_or_prompt_details(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ai.adapters import gemini_api

    class _FailingModels:
        async def generate_content(self, **_kwargs: Any) -> object:
            raise RuntimeError("provider echoed a raw child name: Joana")

    client = SimpleNamespace(aio=SimpleNamespace(models=_FailingModels()))
    monkeypatch.setattr(gemini_api, "_get_vertex_client", lambda _location: client)

    with pytest.raises(GeminiApiError) as exc_info:
        await gemini_api._generate_vertex(
            "private author draft", model="gemini-2.5-flash", max_output_tokens=32
        )
    message = str(exc_info.value)
    assert "RuntimeError" in message
    assert "Joana" not in message
    assert "private author draft" not in message


@pytest.mark.asyncio
async def test_vertex_adapter_rejects_empty_or_invalid_json(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_client, _ = _client_with_response(
        SimpleNamespace(parsed=None, text="not-json", model_version=None)
    )
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex._get_vertex_client", lambda _location: fake_client
    )

    with pytest.raises(GeminiApiError, match="invalid JSON"):
        await GeminiVertexAiClient().generate_insight(
            prompt_id="insight_family_weekly",
            prompt_version="v1",
            user_payload={"system_prompt": "safe", "user_message": "summary"},
            response_schema={"type": "object"},
        )


@pytest.mark.asyncio
async def test_vertex_healthcheck_targets_configured_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_client, models = _client_with_response(object())
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex._get_vertex_client", lambda _location: fake_client
    )
    monkeypatch.setattr(
        "app.ai.adapters.gemini_vertex.settings.gemini_model_name", "gemini-2.5-flash"
    )

    await GeminiVertexAiClient().healthcheck()

    assert models.calls == [{"model": "gemini-2.5-flash"}]


@pytest.mark.parametrize(
    ("model", "budget", "level"),
    [
        ("gemini-2.5-flash", 0, None),
        ("gemini-3.1-flash-lite", None, "MINIMAL"),
        ("gemini-3.5-flash", None, "MINIMAL"),
        ("gemini-3.8-flash", None, "LOW"),
    ],
)
def test_thinking_config_uses_each_generations_floor(
    model: str, budget: int | None, level: str | None
) -> None:
    from app.ai.adapters.gemini_api import thinking_config

    config = thinking_config(model)
    assert config.thinking_budget == budget
    assert config.thinking_level == level


@pytest.mark.asyncio
async def test_generate_text_uses_gemini_location_and_optional_json_mode(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ai.adapters import gemini_api

    fake_client, models = _client_with_response(SimpleNamespace(text='{"ok": true}'))
    locations: list[str] = []

    def _client(location: str) -> object:
        locations.append(location)
        return fake_client

    monkeypatch.setattr(gemini_api, "_get_vertex_client", _client)
    monkeypatch.setattr(gemini_api.settings, "ai_provider", "gemini_vertex")
    monkeypatch.setattr(gemini_api.settings, "gemini_location", "eu")

    await gemini_api.generate_text(
        "brief", model="gemini-3.5-flash", response_mime_type="application/json"
    )
    await gemini_api.generate_text("brief", model="gemini-3.5-flash")

    assert locations == ["eu", "eu"]
    assert models.calls[0]["config"].response_mime_type == "application/json"
    assert models.calls[1]["config"].response_mime_type is None


_PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16


def _image_response(data: bytes | None, finish_reason: str = "STOP") -> object:
    parts = [SimpleNamespace(inline_data=SimpleNamespace(data=data, mime_type="image/png"))]
    content = SimpleNamespace(parts=parts if data is not None else [])
    return SimpleNamespace(
        candidates=[SimpleNamespace(content=content, finish_reason=finish_reason)],
        prompt_feedback=None,
    )


@pytest.mark.asyncio
async def test_generate_image_uses_image_location_and_a_png_image_request(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ai.adapters import gemini_api

    fake_client, models = _client_with_response(_image_response(_PNG))
    locations: list[str] = []

    def _client(location: str) -> object:
        locations.append(location)
        return fake_client

    monkeypatch.setattr(gemini_api, "_vertex_client", _client)
    monkeypatch.setattr(gemini_api.settings, "ai_provider", "gemini_vertex")
    monkeypatch.setattr(gemini_api.settings, "image_location", "global")
    monkeypatch.setattr(gemini_api.settings, "image_model_name", "gemini-3.1-flash-lite-image")

    assert await gemini_api.generate_image("a red apple", aspect_ratio="4:3") == _PNG

    assert locations == ["global"]
    call = models.calls[0]
    config = call["config"]
    assert call["model"] == "gemini-3.1-flash-lite-image"
    assert config.response_modalities == ["IMAGE"]
    assert config.image_config.aspect_ratio == "4:3"
    assert config.image_config.output_mime_type == "image/png"
    assert config.image_config.person_generation == "ALLOW_NONE"
    assert "Never draw people" in config.system_instruction
    assert {str(s.threshold).rsplit(".", 1)[-1] for s in config.safety_settings} == {
        "BLOCK_LOW_AND_ABOVE"
    }


@pytest.mark.asyncio
@pytest.mark.parametrize("data", [None, b"\xff\xd8\xff\xe0 jpeg"])
async def test_generate_image_fails_without_a_png(
    monkeypatch: pytest.MonkeyPatch, data: bytes | None
) -> None:
    from app.ai.adapters import gemini_api

    fake_client, _ = _client_with_response(_image_response(data, finish_reason="IMAGE_SAFETY"))
    monkeypatch.setattr(gemini_api, "_vertex_client", lambda _location: fake_client)
    monkeypatch.setattr(gemini_api.settings, "ai_provider", "gemini_vertex")

    with pytest.raises(GeminiApiError):
        await gemini_api.generate_image("a child reading")


def test_only_image_generation_may_use_a_non_eu_client(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.ai.adapters import gemini_api

    monkeypatch.setitem(gemini_api._vertex_clients, "global", object())
    with pytest.raises(GeminiApiError, match="EU"):
        gemini_api._get_vertex_client("global")
