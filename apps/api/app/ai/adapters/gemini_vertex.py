"""Structured-output Gemini adapter for Vertex AI EU."""

from __future__ import annotations

import asyncio
import copy
import json
import secrets
from typing import Any
from uuid import UUID

from app.ai.adapters.gemini_api import GeminiApiError, _get_vertex_client, thinking_config
from app.ai.pseudonymise import assert_no_internal_identifiers, assert_no_tenant_id
from app.ai.text_model import resolve_text_model
from app.config.settings import settings

_TIMEOUT_SECONDS = 30


def _build_source_aliases(source_ids: object) -> dict[str, str]:
    """Map stable database UUIDs to unlinkable aliases used only for one provider call."""
    if not isinstance(source_ids, list):
        raise GeminiApiError("Vertex insight source_up_ids must be a list")
    if len(source_ids) > 10:
        raise GeminiApiError("Vertex insight source_up_ids exceeds the evidence limit")

    nonce = secrets.token_urlsafe(8)
    aliases: dict[str, str] = {}
    for index, source_id in enumerate(source_ids, start=1):
        try:
            canonical_id = str(UUID(str(source_id)))
        except (TypeError, ValueError, AttributeError) as exc:
            raise GeminiApiError("Vertex insight source_up_ids contains an invalid UUID") from exc
        aliases[f"UP-{nonce}-{index}"] = canonical_id
    return aliases


def _provider_response_schema(
    response_schema: dict[str, Any], *, allowed_aliases: list[str]
) -> dict[str, Any]:
    """Constrain provider evidence citations to request-local aliases, never database IDs."""
    schema = copy.deepcopy(response_schema)
    properties = schema.setdefault("properties", {})
    item_schema: dict[str, Any] = {"type": "string"}
    if allowed_aliases:
        item_schema["enum"] = allowed_aliases
    properties["source_up_ids"] = {
        "type": "array",
        "items": item_schema,
        "maxItems": len(allowed_aliases),
    }
    return schema


class GeminiVertexAiClient:
    """Generate validated-shape JSON without logging prompt or response content."""

    async def generate_insight(
        self,
        *,
        prompt_id: str,
        prompt_version: str,
        user_payload: dict[str, Any],
        response_schema: dict[str, Any],
    ) -> dict:
        from google.genai import types

        assert_no_tenant_id(user_payload)
        assert_no_internal_identifiers(user_payload)
        system_prompt = user_payload.get("system_prompt")
        user_message = user_payload.get("user_message")
        if not isinstance(system_prompt, str) or not system_prompt.strip():
            raise GeminiApiError("Vertex insight system prompt is missing")
        if not isinstance(user_message, str) or not user_message.strip():
            raise GeminiApiError("Vertex insight user message is missing")

        source_aliases = _build_source_aliases(user_payload.get("source_up_ids", []))
        evidence = ",".join(source_aliases)
        contents = (
            f"{user_message}\n\nAllowed evidence aliases (use only these values): [{evidence}]"
        )
        provider_schema = _provider_response_schema(
            response_schema, allowed_aliases=list(source_aliases)
        )

        model = await resolve_text_model()
        config = types.GenerateContentConfig(
            system_instruction=system_prompt,
            max_output_tokens=1024,
            temperature=0.3,
            response_mime_type="application/json",
            response_json_schema=provider_schema,
            thinking_config=thinking_config(model),
            safety_settings=[
                types.SafetySetting(
                    category=category,
                    threshold=types.HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
                )
                for category in (
                    types.HarmCategory.HARM_CATEGORY_HARASSMENT,
                    types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                    types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                    types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                )
            ],
        )

        try:
            client = _get_vertex_client(settings.gemini_location)
            async with asyncio.timeout(_TIMEOUT_SECONDS):
                response = await client.aio.models.generate_content(
                    model=model,
                    contents=contents,
                    config=config,
                )
        except TimeoutError as exc:
            raise GeminiApiError("Vertex insight generation timed out") from exc
        except GeminiApiError:
            raise
        except Exception as exc:
            raise GeminiApiError(f"Vertex insight generation failed: {type(exc).__name__}") from exc

        parsed: Any = getattr(response, "parsed", None)
        if hasattr(parsed, "model_dump"):
            parsed = parsed.model_dump()
        if not isinstance(parsed, dict):
            text = getattr(response, "text", None)
            if not isinstance(text, str) or not text.strip():
                raise GeminiApiError("Vertex insight generation returned no JSON")
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as exc:
                raise GeminiApiError("Vertex insight generation returned invalid JSON") from exc
        if not isinstance(parsed, dict):
            raise GeminiApiError("Vertex insight generation returned a non-object JSON value")

        cited_aliases = parsed.get("source_up_ids", [])
        if not isinstance(cited_aliases, list) or any(
            not isinstance(alias, str) or alias not in source_aliases for alias in cited_aliases
        ):
            raise GeminiApiError("Vertex insight cited an unknown evidence alias")

        result = dict(parsed)
        result["source_up_ids"] = list(
            dict.fromkeys(source_aliases[alias] for alias in cited_aliases)
        )
        result["prompt_id"] = prompt_id
        result["prompt_version"] = prompt_version
        result["model_id"] = model
        result["model_version"] = getattr(response, "model_version", None) or model
        return result

    async def healthcheck(self) -> None:
        """Confirm the configured publisher model is reachable in the Vertex region."""
        try:
            client = _get_vertex_client(settings.gemini_location)
            async with asyncio.timeout(5):
                await client.aio.models.get(model=await resolve_text_model())
        except TimeoutError as exc:
            raise GeminiApiError("Vertex model healthcheck timed out") from exc
        except GeminiApiError:
            raise
        except Exception as exc:
            raise GeminiApiError(f"Vertex model healthcheck failed: {type(exc).__name__}") from exc
