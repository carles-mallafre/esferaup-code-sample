"""Voice-lock detectors — the enforcement primitives (Plan 026 Step 9).

Two-sided guard:
  - find_forbidden(text) → list of forbidden phrases present (MUST be empty). Includes
    'diagnostic'/'diagnóstico'/'diagnosis' + the streak bans + 🔥 + old brand.
  - missing_required_hedges(text_ca, text_es) → list of languages lacking ANY hedge (MUST be
    empty — the insight ships bilingual, so BOTH languages must hedge).

Plus a cheap heuristic language check (no heavy langdetect dependency at MVP) so the eval can
assert ca/es content; the >=0.95 target is met by the deterministic stub + the reviewed
prompts. A pluggable real detector is an ops follow-up.

These run against the LocalStubAiClient output in the eval harness AND can be reused as a
runtime guard. They are PURE string functions (no I/O) so the eval is fast + reproducible.
"""

from __future__ import annotations

import re

# Cheap stop-word fingerprints for the two languages we ship. Catalan-distinctive vs
# Spanish-distinctive tokens; the presence ratio is a coarse but reliable signal on the
# hedged, reviewed copy (no external langdetect).
_CA_MARKERS = re.compile(
    r"\b(això|aquesta|amb|sense|podria|sembla|potser|cada|infant|moments?)\b", re.IGNORECASE
)
_ES_MARKERS = re.compile(
    r"\b(esto|esta|con|sin|podría|parece|quizá|cada|niñ[oa]s?|momentos?)\b", re.IGNORECASE
)


def find_forbidden(text: str, *, forbidden: list[str] | None = None) -> list[str]:
    """Return every forbidden phrase present in ``text`` (case-insensitive substring)."""
    if forbidden is None:
        from app.ai.prompts import load_forbidden_phrases

        forbidden = load_forbidden_phrases()
    lowered = text.lower()
    hits: list[str] = []
    for phrase in forbidden:
        # The emoji is matched literally (not lowercased meaningfully); substring covers both.
        if phrase.lower() in lowered or phrase in text:
            hits.append(phrase)
    return hits


def has_required_hedge(text: str, lang: str, *, hedges: dict[str, list[str]] | None = None) -> bool:
    """True if ``text`` contains at least one hedge term for ``lang``."""
    if hedges is None:
        from app.ai.prompts import load_required_hedges

        hedges = load_required_hedges()
    lowered = text.lower()
    return any(term.lower() in lowered for term in hedges.get(lang, []))


def missing_required_hedges(
    text_ca: str, text_es: str, *, hedges: dict[str, list[str]] | None = None
) -> list[str]:
    """Return the languages whose body lacks ANY hedge (the two-sided guard — must be empty)."""
    missing: list[str] = []
    if not has_required_hedge(text_ca, "ca", hedges=hedges):
        missing.append("ca")
    if not has_required_hedge(text_es, "es", hedges=hedges):
        missing.append("es")
    return missing


def detect_language(text: str) -> str:
    """Coarse ca/es/unknown detector (marker-token majority). No external dependency."""
    ca = len(_CA_MARKERS.findall(text))
    es = len(_ES_MARKERS.findall(text))
    if ca == 0 and es == 0:
        return "unknown"
    return "ca" if ca >= es else "es"


def passes_voice_lock(*, title_ca: str, title_es: str, body_ca: str, body_es: str) -> bool:
    """True if the insight has 0 forbidden hits AND hedges in both languages."""
    full = f"{title_ca}\n{title_es}\n{body_ca}\n{body_es}"
    if find_forbidden(full):
        return False
    return not missing_required_hedges(body_ca, body_es)
