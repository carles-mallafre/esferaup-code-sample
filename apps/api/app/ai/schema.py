"""Insight Pydantic schema + cache-key / insight-hash helpers (Plan 026 Steps 5-6).

InsightResponse is the structured-output contract the AIClient must satisfy (Vertex
generationConfig.responseSchema enforces it server-side; the stub builds a conformant dict).
The service validates the raw dict against this model, retries ONCE on failure, and on a
second failure returns null + emits AI_INSIGHT_VALIDATION_FAILED.

Locked constraints (Plan 026 "Locked decisions"):
  - source_up_ids max_length=10 (a bigger evidence set indicates a vacuous insight).
  - confidence_band ∈ {low, medium, high}.
  - kind ∈ {plan_recommendation, outburst_tip} — pattern_hint REMOVED per Round-1 critical
    (re-introduced only after the validation study; a separate Phase-2 plan owns it).
  - prompt_id + prompt_version echoed back for the Mobile/Dashboard transparency SHA.
"""

from __future__ import annotations

import hashlib
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, Field


class InsightKind(StrEnum):
    PLAN_RECOMMENDATION = "plan_recommendation"
    OUTBURST_TIP = "outburst_tip"
    # pattern_hint REMOVED per Round-1 critical — gated by the validation study.


class InsightResponse(BaseModel):
    """Validated AI insight. The model's raw JSON is parsed into this (retry-once on fail)."""

    kind: InsightKind
    title_ca: str = Field(..., min_length=1, max_length=120)
    title_es: str = Field(..., min_length=1, max_length=120)
    body_ca: str = Field(..., min_length=1, max_length=1000)
    body_es: str = Field(..., min_length=1, max_length=1000)
    source_up_ids: list[UUID] = Field(default_factory=list, max_length=10)
    confidence_band: str = Field(..., pattern="^(low|medium|high)$")
    disclaimer_required: bool = True
    prompt_id: str = Field(..., max_length=64)
    prompt_version: str = Field(..., max_length=32)
    # Provenance the persisted row records (the model returns these; the stub fills them).
    model_id: str = Field(default="", max_length=64)
    model_version: str = Field(default="", max_length=64)


# The JSON schema the AIClient receives (Vertex responseSchema). Kept minimal + explicit so a
# model bump cannot silently change the contract.
INSIGHT_RESPONSE_SCHEMA: dict = {
    "type": "object",
    "properties": {
        "kind": {"type": "string", "enum": ["plan_recommendation", "outburst_tip"]},
        "title_ca": {"type": "string"},
        "title_es": {"type": "string"},
        "body_ca": {"type": "string"},
        "body_es": {"type": "string"},
        "source_up_ids": {"type": "array", "items": {"type": "string"}, "maxItems": 10},
        "confidence_band": {"type": "string", "enum": ["low", "medium", "high"]},
        "disclaimer_required": {"type": "boolean"},
    },
    "required": [
        "kind",
        "title_ca",
        "title_es",
        "body_ca",
        "body_es",
        "confidence_band",
    ],
}


def insight_cache_key(
    *, tenant_id: UUID, profile_id: UUID, prompt_id: str, prompt_version: str
) -> str:
    """SWR Redis key. prompt_version is IN the key so a version bump/rollback partitions caches
    automatically (the anti-pattern this closes: "Insight cached without prompt_version =
    silent stale data")."""
    return f"ai:insight:{tenant_id}:{profile_id}:{prompt_id}:{prompt_version}"


def insight_hash(*, prompt_id: str, prompt_version: str, source_up_ids: list[UUID]) -> str:
    """Content-stable identifier: sha256(prompt_id || prompt_version || sorted(source_up_ids)).

    The DB dedup index + the dismissal scoping both key off this. Version is part of the hash
    so a prompt bump produces a distinct content identity.
    """
    parts = [prompt_id, prompt_version, *sorted(str(uid) for uid in source_up_ids)]
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
