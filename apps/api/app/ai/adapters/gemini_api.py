"""Vertex Gemini client for the Activa authoring assistant (Plan 037/060).

Inference uses Vertex AI through the google-genai SDK: Gemini text/OCR in
``settings.gemini_location`` (``eu`` multi-region or ``europe-west3``) and read-aloud audio in
``settings.gemini_audio_location``. Activa illustrations use ``settings.image_location``, the one
location allowed outside the EU (ADR-017): their prompts carry no child or family data.
The previous direct AI Studio/API-key path had no enforceable EU-region boundary and is
deliberately unavailable; local/dev/test callers use their explicit deterministic fixture when
``AI_PROVIDER=stub``.
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from app.config.settings import settings
from app.core.google_credentials import load_google_credentials

if TYPE_CHECKING:
    from google import genai

# Product voice locks (CLAUDE.md): no gamification/streaks, no diagnostic claims.
SYSTEM_PREAMBLE = (
    "Ets un assistent per a professionals que creen plans d'aprenentatge per a infants. "
    "Escriu SEMPRE en català, amb to proper i sense pressa. PROHIBIT: ratxes, gamificació "
    "per pressió, o llenguatge diagnòstic. Respon NOMÉS amb el que es demana, sense preàmbuls."
)
_TEXT_TIMEOUT_SECONDS = 30
_IMAGE_TIMEOUT_SECONDS = 60


class GeminiApiError(Exception):
    """Raised when the Gemini call fails or returns an unexpected shape."""


def _is_vertex() -> bool:
    return settings.ai_provider == "gemini_vertex"


def is_available() -> bool:
    """True only when the locked Vertex EU backend is selected and configured."""
    return _is_vertex() and bool(settings.vertex_project)


# ── Vertex AI (google-genai SDK) ─────────────────────────────────────────────────
_vertex_clients: dict[str, genai.Client] = {}  # one lazily-built client per location


def _get_vertex_client(location: str) -> genai.Client:
    if location != "eu" and not location.startswith("europe-"):
        raise GeminiApiError("Vertex location must stay in the EU")
    return _vertex_client(location)


def _vertex_client(location: str) -> genai.Client:
    if location in _vertex_clients:
        return _vertex_clients[location]
    if not settings.vertex_project:
        raise GeminiApiError("VERTEX_PROJECT not configured")
    from google import genai

    credentials = load_google_credentials(settings.google_application_credentials_json)
    # credentials=None → Application Default Credentials (GOOGLE_APPLICATION_CREDENTIALS file).
    client = genai.Client(
        vertexai=True,
        project=settings.vertex_project,
        location=location,
        credentials=credentials,
    )
    _vertex_clients[location] = client
    return client


# Gemini 3 models without the MINIMAL thinking level (Vertex "Thinking" docs, 2026-09).
_LOW_THINKING_FLOOR = ("gemini-3.7-", "gemini-3.8-", "gemini-3.1-pro", "gemini-3-pro")


def thinking_config(model: str):
    """The least thinking each model allows. Thinking tokens are billed as output.

    Gemini 2.x turns thinking off with ``thinking_budget=0`` and rejects ``thinking_level``.
    Gemini 3+ is controlled with ``thinking_level``; MINIMAL is the floor, LOW for some models.
    """
    from google.genai import types

    if model.startswith("gemini-2."):
        return types.ThinkingConfig(thinking_budget=0)
    if model.startswith(_LOW_THINKING_FLOOR):
        return types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW)
    return types.ThinkingConfig(thinking_level=types.ThinkingLevel.MINIMAL)


async def _generate_vertex(
    prompt: str,
    *,
    model: str,
    max_output_tokens: int,
    system_instruction: str = SYSTEM_PREAMBLE,
    temperature: float = 0.7,
    location: str | None = None,
    response_mime_type: str | None = None,
) -> str:
    from google.genai import types

    client = _get_vertex_client(location or settings.gemini_location)
    try:
        async with asyncio.timeout(_TEXT_TIMEOUT_SECONDS):
            resp = await client.aio.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=system_instruction,
                    max_output_tokens=max_output_tokens,
                    temperature=temperature,
                    response_mime_type=response_mime_type,
                    # Thinking would spend the output budget on reasoning and can leave no
                    # visible text for short tasks like title lists.
                    thinking_config=thinking_config(model),
                ),
            )
    except TimeoutError as exc:
        raise GeminiApiError("Vertex generateContent timed out") from exc
    except Exception as exc:  # SDK raises a variety of google.api_core errors
        raise GeminiApiError(f"Vertex generateContent failed: {type(exc).__name__}") from exc
    text = resp.text
    if not text:
        raise GeminiApiError("Vertex returned no text")
    return text


# ── Text generation (Vertex AI EU only) ─────────────────────────────────────────
async def generate_text(
    prompt: str,
    *,
    model: str,
    max_output_tokens: int = 1024,
    system_instruction: str = SYSTEM_PREAMBLE,
    temperature: float = 0.7,
    location: str | None = None,
    response_mime_type: str | None = None,
) -> str:
    """Generate text through Vertex EU, failing closed for every other provider setting.

    ``location`` overrides ``settings.gemini_location`` for callers with their own model
    setting (Luma comprehension); it must be ``eu`` or a ``europe-*`` region.

    ``response_mime_type="application/json"`` makes Vertex return syntactically valid JSON;
    Gemini 3.5 models emit malformed JSON for the long Activa plan prompt without it.
    """
    if not _is_vertex():
        raise GeminiApiError("Text generation requires ai_provider='gemini_vertex'")
    return await _generate_vertex(
        prompt,
        model=model,
        max_output_tokens=max_output_tokens,
        system_instruction=system_instruction,
        temperature=temperature,
        location=location,
        response_mime_type=response_mime_type,
    )


# ── Image generation (Gemini image model, Activa illustrations) ─────────────────
# Fixed on every image request, beneath the admin-editable ``activa.image_framing`` prompt.
IMAGE_SYSTEM_INSTRUCTION = (
    "You illustrate learning activities for children. Always draw a flat, simple, "
    "non-photorealistic illustration with no text. Never draw people. If the request "
    "involves people, show the scene with animals or objects instead."
)
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def image_is_available() -> bool:
    """True when image generation is configured (Vertex provider + project)."""
    return _is_vertex() and bool(settings.vertex_project)


async def generate_image(prompt: str, *, aspect_ratio: str = "1:1") -> bytes:
    """Generate one illustration from a prompt via ``settings.image_model_name``. Returns PNG.

    The client is built for ``settings.image_location`` without the EU check, which is the
    residency exemption for this caller only (ADR-017).
    """
    if not _is_vertex():
        raise GeminiApiError("Image generation requires ai_provider='gemini_vertex'")
    from google.genai import types

    client = _vertex_client(settings.image_location)
    try:
        async with asyncio.timeout(_IMAGE_TIMEOUT_SECONDS):
            resp = await client.aio.models.generate_content(
                model=settings.image_model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction=IMAGE_SYSTEM_INSTRUCTION,
                    response_modalities=["IMAGE"],
                    candidate_count=1,
                    # A children's product must not synthesise images of people (Art. 9 /
                    # child-safety posture): Vertex refuses any image containing a person.
                    image_config=types.ImageConfig(
                        aspect_ratio=aspect_ratio,
                        output_mime_type="image/png",
                        person_generation="ALLOW_NONE",
                    ),
                    safety_settings=[
                        types.SafetySetting(
                            category=category,
                            threshold=types.HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
                        )
                        for category in (
                            types.HarmCategory.HARM_CATEGORY_HARASSMENT,
                            types.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                            types.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                            types.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                        )
                    ],
                ),
            )
    except TimeoutError as exc:
        raise GeminiApiError("Vertex image generation timed out") from exc
    except Exception as exc:  # SDK raises a variety of google.api_core errors
        raise GeminiApiError(f"Vertex image generation failed: {type(exc).__name__}") from exc

    candidate = (resp.candidates or [None])[0]
    parts = (candidate.content.parts if candidate and candidate.content else None) or []
    for part in parts:
        data = part.inline_data.data if part.inline_data else None
        if data:
            if not data.startswith(_PNG_SIGNATURE):
                raise GeminiApiError("Vertex returned a non-PNG image")
            return data
    reason = candidate.finish_reason if candidate else resp.prompt_feedback
    raise GeminiApiError(f"Vertex returned no image (likely safety-filtered): {reason}")
