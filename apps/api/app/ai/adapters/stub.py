"""LocalStubAiClient — deterministic dev/test AI adapter (Plan 026 Step 1).

Mirrors the LocalKmsAdapter / StubOcrEngine pattern: a real-shaped implementation that
needs no external service and no network. Returns CANNED structured insights that:

  - Conform to the InsightResponse Pydantic schema (title/body ca+es, source_up_ids,
    confidence_band, disclaimer_required, prompt_id, prompt_version).
  - Carry the REQUIRED HEDGE phrases (Plan 080 required_hedges.yaml) so the voice-lock
    eval harness's two-sided guard (forbidden-phrase=0 AND required-hedge>=1) passes
    against the stub's own output.
  - Contain ZERO forbidden phrases (no 'diagnostic'/'diagnóstico'/'streak'/'racha'/'ratxa',
    no 🔥) — AI Patrons are HYPOTHETICAL PATTERNS, never diagnoses (CLAUDE.md voice-lock).
  - Are written in valid Catalan + Spanish (>=0.95 language-detect target).

Determinism: the output is a pure function of (prompt_id, prompt_version, user_payload).
The same inputs yield byte-identical text so the eval harness + SWR cache tests are
reproducible and a retry of a transient failure is idempotent.

NO Mistral/OpenAI/Anthropic/Azure — and no Vertex either; this is the local stand-in that
backs both the AI Patrons pipeline and the Arxiu OCR engine in dev/test.
"""

from __future__ import annotations

import hashlib

# Canned, hedged, voice-lock-compliant bodies per insight kind. The {tag} placeholder is a
# short content digest so two different payloads produce visibly different (but still
# deterministic + hedged) text — never any real PII (the payload is already pseudonymised).
_CANNED: dict[str, dict[str, str]] = {
    "insight_family_weekly": {
        "title_ca": "Una possible tendència aquesta setmana",
        "title_es": "Una posible tendencia esta semana",
        "body_ca": (
            "Sembla que aquesta setmana hi ha hagut més moments registrats al voltant "
            "del descans. Podria ser que un ritme més tranquil al vespre ajudi; potser "
            "val la pena observar-ho sense pressa els propers dies. Això és una hipòtesi, "
            "no una conclusió: cada infant és diferent. Ref {tag}."
        ),
        "body_es": (
            "Parece que esta semana ha habido más momentos registrados alrededor del "
            "descanso. Podría ser que un ritmo más tranquilo por la tarde ayude; quizá "
            "valga la pena observarlo sin prisa los próximos días. Esto es una hipótesis, "
            "no una conclusión: cada niño o niña es diferente. Ref {tag}."
        ),
        "confidence_band": "low",
    },
    "insight_outburst_tip": {
        "title_ca": "Una idea per acompanyar els moments difícils",
        "title_es": "Una idea para acompañar los momentos difíciles",
        "body_ca": (
            "Davant d'un moment de tensió, de vegades ajuda anticipar un espai tranquil i "
            "previsible. Potser provar-ho quan detecteu els primers senyals podria donar "
            "marge. És només una suggerència orientativa i no substitueix l'acompanyament "
            "d'un professional. Ref {tag}."
        ),
        "body_es": (
            "Ante un momento de tensión, a veces ayuda anticipar un espacio tranquilo y "
            "previsible. Quizá probarlo cuando detectéis las primeras señales podría dar "
            "margen. Es solo una sugerencia orientativa y no sustituye el acompañamiento "
            "de un profesional. Ref {tag}."
        ),
        "confidence_band": "low",
    },
}

# Default fallback for any prompt_id not in _CANNED (keeps the contract total).
_DEFAULT = _CANNED["insight_family_weekly"]

_STUB_MODEL_ID = "stub-ai"
_STUB_MODEL_VERSION = "v1"


class LocalStubAiClient:
    """Deterministic, hedged, voice-lock-compliant AI stand-in for dev/test."""

    async def generate_insight(
        self,
        *,
        prompt_id: str,
        prompt_version: str,
        user_payload: dict,
        response_schema: dict,
    ) -> dict:
        canned = _CANNED.get(prompt_id, _DEFAULT)
        tag = self._payload_tag(prompt_id, prompt_version, user_payload)

        # source_up_ids: echo back the (already-bounded) ids the caller pseudonymised in,
        # capped at the schema's max_length of 10. The service FK-validates them again.
        source_up_ids = list(user_payload.get("source_up_ids", []))[:10]

        return {
            "kind": _kind_for_prompt(prompt_id),
            "title_ca": canned["title_ca"],
            "title_es": canned["title_es"],
            "body_ca": canned["body_ca"].format(tag=tag),
            "body_es": canned["body_es"].format(tag=tag),
            "source_up_ids": source_up_ids,
            "confidence_band": canned["confidence_band"],
            "disclaimer_required": True,
            "prompt_id": prompt_id,
            "prompt_version": prompt_version,
            "model_id": _STUB_MODEL_ID,
            "model_version": _STUB_MODEL_VERSION,
        }

    @staticmethod
    def _payload_tag(prompt_id: str, prompt_version: str, user_payload: dict) -> str:
        """A short deterministic digest of the pseudonymised payload (no PII)."""
        basis = f"{prompt_id}|{prompt_version}|{sorted(user_payload.get('source_up_ids', []))}"
        return hashlib.sha256(basis.encode("utf-8")).hexdigest()[:8]


def _kind_for_prompt(prompt_id: str) -> str:
    """Map a prompt id to its InsightKind value (MVP: 2 kinds)."""
    if prompt_id == "insight_outburst_tip":
        return "outburst_tip"
    return "plan_recommendation"
