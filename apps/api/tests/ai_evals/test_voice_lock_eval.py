"""Plan 026 Step 9 — the voice-lock eval harness (the enforcement).

Runs the LocalStubAiClient on synthetic golden fixtures and asserts the two-sided guard:
  - 0 forbidden-phrase hits (incl. 'diagnostic'/'diagnóstico'/'diagnosis').
  - required hedge present in BOTH ca AND es bodies.
  - 100% structured-output schema validation.
  - >=0.95 ca/es language detection on the golden set.

Plus a test-of-the-test: the detector itself MUST catch known-bad outputs.
"""

from __future__ import annotations

import uuid

import pytest

from app.ai.adapters.stub import LocalStubAiClient
from app.ai.schema import INSIGHT_RESPONSE_SCHEMA, InsightResponse
from app.ai.voice_lock import (
    detect_language,
    find_forbidden,
    missing_required_hedges,
)
from tests.ai_evals.fixtures import (
    BAD_OUTPUTS_FORBIDDEN,
    GOLDEN_INPUTS,
    NEURODIVERGENT_INPUTS,
    NON_HEDGED_CA,
    NON_HEDGED_ES,
)

pytestmark = pytest.mark.asyncio

_ALL_INPUTS = GOLDEN_INPUTS + NEURODIVERGENT_INPUTS


async def _stub_outputs() -> list[InsightResponse]:
    client = LocalStubAiClient()
    out: list[InsightResponse] = []
    for fx in _ALL_INPUTS:
        raw = await client.generate_insight(
            prompt_id=fx["prompt_id"],
            prompt_version="v1",
            user_payload={"source_up_ids": [str(uuid.uuid4())], **fx},
            response_schema=INSIGHT_RESPONSE_SCHEMA,
        )
        out.append(InsightResponse.model_validate(raw))
    return out


async def test_eval_forbidden_phrases_zero_hits() -> None:
    """Every golden-fixture insight has ZERO forbidden phrases (the voice-lock)."""
    for ins in await _stub_outputs():
        full = f"{ins.title_ca}\n{ins.title_es}\n{ins.body_ca}\n{ins.body_es}"
        hits = find_forbidden(full)
        assert hits == [], f"forbidden phrases leaked: {hits}"


async def test_eval_required_hedges_present() -> None:
    """Every insight hedges in BOTH ca and es (the two-sided guard)."""
    for ins in await _stub_outputs():
        missing = missing_required_hedges(ins.body_ca, ins.body_es)
        assert missing == [], f"missing hedges in: {missing}"


async def test_eval_schema_validation_100pct() -> None:
    """Every stub output validates against InsightResponse (100% schema pass)."""
    outputs = await _stub_outputs()
    assert len(outputs) == len(_ALL_INPUTS)  # all parsed without raising


async def test_eval_language_detection_ge_095() -> None:
    """>=95% of bodies are detected as the expected language (ca for body_ca, es for body_es)."""
    outputs = await _stub_outputs()
    total = len(outputs) * 2
    correct = 0
    for ins in outputs:
        if detect_language(ins.body_ca) == "ca":
            correct += 1
        if detect_language(ins.body_es) == "es":
            correct += 1
    assert correct / total >= 0.95, f"language detection {correct}/{total}"


async def test_detector_catches_forbidden_outputs() -> None:
    """Test-of-the-test: the detector MUST flag every known-bad output (incl. diagnostic)."""
    for bad in BAD_OUTPUTS_FORBIDDEN:
        assert find_forbidden(bad), f"detector missed a forbidden output: {bad!r}"
    # Specifically the diagnostic bans (ca + es).
    assert "diagnòstic" in " ".join(find_forbidden(BAD_OUTPUTS_FORBIDDEN[0])) or find_forbidden(
        BAD_OUTPUTS_FORBIDDEN[0]
    )
    assert any("diagn" in h for h in find_forbidden("Esto es un diagnóstico claro."))


async def test_detector_flags_missing_hedges() -> None:
    """Test-of-the-test: a non-hedged bilingual pair is flagged in BOTH languages."""
    missing = missing_required_hedges(NON_HEDGED_CA, NON_HEDGED_ES)
    assert set(missing) == {"ca", "es"}
