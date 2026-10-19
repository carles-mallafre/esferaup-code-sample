"""AIClient Protocol — the pluggable AI text-generation contract (Plan 026 Step 1).

The integration point is a single method:
    AIClient.generate_insight(prompt_id, prompt_version, user_payload, response_schema) -> dict

Concrete adapters live in app/ai/adapters/ and are selected at startup by
settings.ai_provider ("stub" | "gemini_vertex") — mirroring the KMS/OCR/push adapter
pattern (app.kms.get_kms_adapter / app.ocr.get_ocr_engine / app.push.get_push_provider).

The production adapter uses Gemini Flash on Vertex AI EU (europe-west3, Frankfurt) with
server-enforced JSON Schema output. LocalStubAiClient keeps the same pipeline reproducible
in dev/test without an external dependency. The feature gate remains independent of provider
selection, so production OCR can use Vertex while family-facing insights remain dark.

CRITICAL invariant (the security boundary): the AIClient NEVER sees raw PII. Callers MUST
run app.ai.pseudonymise.pseudonymise() on the user_payload before this method, and MUST NOT
put tenant_id in the payload (Vertex routing is per-service-account, never per-tenant). The
client is the LAST step; it is not trusted to redact.

This module must stay import-light (stdlib + typing only) so the Protocol can be referenced
from the service layer without dragging the vertexai SDK into the import graph.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class AIClient(Protocol):
    """Generate a structured insight from a pseudonymised payload.

    Implementations MUST:
      - Return a JSON-shaped dict conforming to ``response_schema`` (Vertex
        ``generationConfig.responseSchema`` enforces this server-side; the stub
        constructs a conformant dict directly).
      - Be deterministic for a given (prompt_id, prompt_version, user_payload) in
        dev/test (the stub) so the eval harness is reproducible.
      - Raise on engine failure — the caller maps it to 503 AI_PIPELINE_ERROR
        (flag-gated; never breaks a family flow).
      - NEVER log or persist the prompt content or the raw response (Plan 008
        redaction + Plan 026 observability — hashes + metadata only).
    """

    async def generate_insight(
        self,
        *,
        prompt_id: str,
        prompt_version: str,
        user_payload: dict,
        response_schema: dict,
    ) -> dict:
        """Return a structured insight dict (validated by the service against InsightResponse)."""
        ...


_client_instance: AIClient | None = None


def get_ai_client() -> AIClient:
    """Return the process-singleton AI client (lazy).

    Called by the InsightService and used by the OCR adapter to distinguish the deterministic
    local path from the shared real Vertex configuration. The singleton is initialised lazily,
    so importing this module during test collection needs no Vertex credentials. Tests inject a
    fake via _set_ai_client_for_testing.
    """
    global _client_instance
    if _client_instance is None:
        _client_instance = _build_client()
    return _client_instance


def _build_client() -> AIClient:
    from app.config.settings import settings

    provider = settings.ai_provider
    if provider == "stub":
        from app.ai.adapters.stub import LocalStubAiClient

        return LocalStubAiClient()
    if provider == "gemini_vertex":
        from app.ai.adapters.gemini_vertex import GeminiVertexAiClient

        return GeminiVertexAiClient()
    raise ValueError(f"Unknown ai_provider: {provider!r}. Must be 'stub' or 'gemini_vertex'.")


def _set_ai_client_for_testing(client: AIClient | None) -> None:
    """Inject (or reset) the AI client singleton. Test use only."""
    global _client_instance
    _client_instance = client


__all__ = [
    "AIClient",
    "_set_ai_client_for_testing",
    "get_ai_client",
]
