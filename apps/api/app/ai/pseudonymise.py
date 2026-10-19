"""Pseudonymisation pipeline — THE security boundary before any AI call (Plan 026 Step 3).

GDPR Art. 4(5) PSEUDONYMISATION (the legally precise term — NOT "anonymisation"). The model
is NEVER trusted to redact PII it encounters; we strip direct identifiers BEFORE the call.
This is the anti-pattern this module exists to close: "skipping NER + relying on system-prompt
instructions" (Plan 026 anti-patterns) and "per-request tenant_id in the Vertex payload".

Transform order (applied to every free-text field + the structured fields):
  1. Replace known PROFILE NAMES from the tenant record with deterministic-per-session
     placeholders (randomised across sessions so the same child is not re-linkable across
     two computations). Done FIRST so a name embedded mid-sentence is gone before NER.
  2. NER over free text (pluggable): regex is an explicit dev/test stub. Production AI
     processing requires the manifest-pinned spaCy ca/es/en models and a signed artifact review;
     it fails closed if any artifact or evidence is missing.
  3. EMAIL + PHONE regex → placeholders.
  4. DATES older than 90 days → bucketed to month-year only (recent dates kept for recency
     signal; old precise dates are a re-identification vector).
  5. STRIP tenant_id from the payload entirely — Vertex routing is per-service-account, never
     per-tenant (the tenant identity stays in our DB + cache layer ONLY).

The output payload is what the AIClient sees. The eval harness has indirect-re-identification
fixtures; the Catalan NER recall gap is an acknowledged residual risk documented in the DPIA.
"""

from __future__ import annotations

import re
import secrets
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from app.ai.ner_artifacts import (
    NerArtifactUnavailableError,
    SupportedLocale,
    load_ner_artifact_manifest,
    verified_ner_model,
    verify_installed_ner_artifacts,
)

# ── Direct-identifier regexes (locale-agnostic) ──────────────────────────────────
_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
# Permissive international/ES phone: a +NN prefixed run, OR a 9+ digit run that uses a space
# or parenthesis separator (so a dash-only YYYY-MM-DD date is NOT mis-captured as a phone —
# dates are handled separately and recent ones are kept).
_PHONE_RE = re.compile(r"(?<!\d)(?:\+\d[\d\s().-]{7,}\d|\d{2,}[\s()][\d\s().-]{5,}\d)(?!\d)")
# ISO-ish dates (YYYY-MM-DD) + common DD/MM/YYYY — bucketed by the date handler.
_ISO_DATE_RE = re.compile(r"\b(\d{4})-(\d{2})-(\d{2})\b")
_DMY_DATE_RE = re.compile(r"\b(\d{2})[/.](\d{2})[/.](\d{4})\b")
_UUID_RE = re.compile(
    r"(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
    r"[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])"
)

# Capitalised-token heuristic for the regex NER stub: a Title-Case word of length >= 3 that
# is not a known common word. Deliberately conservative (high precision over recall) — the
# real spaCy engine (ops) lifts recall. Sentence-initial words are NOT auto-redacted (they
# are commonly capitalised), only Title-Case tokens that appear mid-sentence.
_NAME_TOKEN_RE = re.compile(r"(?<!^)(?<![.!?]\s)\b([A-ZÀ-Ÿ][a-zà-ÿ]{2,})\b")

_NAME_PLACEHOLDER = "[NOM]"
_EMAIL_PLACEHOLDER = "[CORREU]"
_PHONE_PLACEHOLDER = "[TELEFON]"
_ENTITY_PLACEHOLDER = "[ENTITAT]"

# These keys identify an EsferaUp data subject or tenancy boundary. They are removed at every
# nesting level, not just at the top of a payload. ``source_up_ids`` is handled separately by
# the Vertex adapter: it replaces each stable UUID with a random request-local alias.
_INTERNAL_IDENTIFIER_KEYS = frozenset(
    {
        "actoruserid",
        "childid",
        "documentid",
        "exerciciid",
        "familyid",
        "fascicleid",
        "id",
        "insightid",
        "membershipid",
        "observationid",
        "placeid",
        "planid",
        "profileid",
        "tenantid",
        "threadid",
        "upid",
        "userid",
    }
)
_SPACY_REDACT_LABELS = frozenset({"FAC", "GPE", "LOC", "MISC", "ORG", "PER", "PERSON"})


class PseudonymisationUnavailableError(NerArtifactUnavailableError):
    """The configured production-grade pseudonymisation boundary is unavailable."""


@dataclass(frozen=True, slots=True)
class NerRedactionResult:
    text: str
    confidence: float


@dataclass(frozen=True, slots=True)
class PseudonymisationResult:
    """Typed output from the final pre-provider privacy boundary."""

    payload: dict[str, Any]
    locale: SupportedLocale
    artifact_manifest_version: str
    artifact_identity: str
    confidence: float

    @property
    def catalan_confidence_requires_skip(self) -> bool:
        manifest = load_ner_artifact_manifest()
        return self.locale == "ca" and self.confidence < manifest.catalan_skip_below


def _canonical_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def _bucket_old_dates(text: str, *, now_iso_year: int, now_iso_month: int) -> str:
    """Replace dates older than ~90 days with month-year only (cheap month-granularity check).

    A precise old date is a re-identification vector; recent dates are kept for the recency
    signal the insight needs. We approximate "older than 90 days" at month granularity (any
    date more than 3 calendar months back), which is conservative and locale-stable.
    """
    cutoff = now_iso_year * 12 + now_iso_month - 3  # 3 months back, in absolute months

    def _iso(m: re.Match[str]) -> str:
        y, mo, _d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f"{y:04d}-{mo:02d}" if (y * 12 + mo) <= cutoff else m.group(0)

    def _dmy(m: re.Match[str]) -> str:
        _d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f"{y:04d}-{mo:02d}" if (y * 12 + mo) <= cutoff else m.group(0)

    text = _ISO_DATE_RE.sub(_iso, text)
    text = _DMY_DATE_RE.sub(_dmy, text)
    return text


def _ner_redact_regex(text: str) -> str:
    """Regex NER stub: redact capitalised name-like tokens (email/phone already removed)."""
    return _NAME_TOKEN_RE.sub(_NAME_PLACEHOLDER, text)


def _redact_text_field(
    text: str,
    *,
    name_map: dict[str, str],
    locale: SupportedLocale,
    now_year: int,
    now_month: int,
) -> NerRedactionResult:
    """Full per-field transform: structured identifiers FIRST, then names, then dates.

    Email + phone are redacted as WHOLE UNITS before the name passes, so a name appearing in
    the local-part of an email (e.g. marc@…) does not split the email into a half-redacted
    string — the entire address collapses to [CORREU].
    """
    from app.config.settings import settings

    # 4. DATES first — bucket old dates to month-year (recent kept). Done before the phone
    # regex so a YYYY-MM-DD is not mis-captured as a phone-number digit run.
    text = _bucket_old_dates(text, now_iso_year=now_year, now_iso_month=now_month)

    # 3. Structured identifiers — whole-unit email + phone.
    text = _EMAIL_RE.sub(_EMAIL_PLACEHOLDER, text)
    text = _PHONE_RE.sub(_PHONE_PLACEHOLDER, text)

    # 1. Known profile names (deterministic placeholder per session).
    for real_name, placeholder in name_map.items():
        if real_name:
            text = re.sub(
                r"\b" + re.escape(real_name) + r"\b", placeholder, text, flags=re.IGNORECASE
            )

    # 2. NER over the remaining free text. Regex is explicit dev/test only; the request gate
    # refuses production inference unless the exact reviewed ca/es/en artifacts are available.
    use_spacy = settings.ai_ner_engine == "spacy"
    if use_spacy:
        return _ner_redact_spacy(text, locale=locale)

    return NerRedactionResult(text=_ner_redact_regex(text), confidence=1.0)


def assert_production_pseudonymisation_ready() -> None:
    """Refuse production AI unless the exact ca/es/en artifacts have signed review."""
    from app.config.settings import settings

    if settings.environment != "production":
        return
    if settings.ai_ner_engine != "spacy":
        raise PseudonymisationUnavailableError(
            "AI_NER_ENGINE=spacy is required for production AI processing"
        )
    try:
        verify_installed_ner_artifacts(require_signed_review=True)
    except NerArtifactUnavailableError as exc:
        raise PseudonymisationUnavailableError(str(exc)) from exc


def _ner_redact_spacy(
    text: str, *, locale: SupportedLocale
) -> NerRedactionResult:  # pragma: no cover - production image only
    """Redact locale-specific entities and return a conservative beam confidence."""
    manifest = load_ner_artifact_manifest()
    if len(text) > manifest.max_text_chars:
        raise PseudonymisationUnavailableError("NER text exceeds the bounded input size")
    try:
        with verified_ner_model(locale) as nlp:
            doc = nlp(text)
            ner = nlp.get_pipe("ner")
            with nlp.select_pipes(disable=["ner"]):
                beam_doc = nlp(text)
            beams = ner.beam_parse(
                [beam_doc],
                beam_width=manifest.beam_width,
                beam_density=manifest.beam_density,
            )
            score_map = ner.scored_ents(beams)[0]

            spans: set[tuple[int, int]] = set()
            confidences: list[float] = []
            for entity in doc.ents:
                if entity.label_ not in _SPACY_REDACT_LABELS:
                    continue
                spans.add((int(entity.start_char), int(entity.end_char)))
                confidences.append(
                    float(score_map.get((entity.start, entity.end, entity.label_), 0.0))
                )

            # Also redact low-probability sensitive candidates. They lower confidence and cause
            # the Catalan Q77 skip, but are removed before the in-memory result is discarded.
            for (start_token, end_token, label), score in score_map.items():
                if label not in _SPACY_REDACT_LABELS or score < manifest.redaction_candidate_floor:
                    continue
                span = beam_doc[start_token:end_token]
                spans.add((int(span.start_char), int(span.end_char)))
                confidences.append(float(score))
            if not spans:
                return NerRedactionResult(text=text, confidence=1.0)

            merged: list[tuple[int, int]] = []
            for start, end in sorted(spans):
                if merged and start <= merged[-1][1]:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], end))
                else:
                    merged.append((start, end))

            parts: list[str] = []
            cursor = 0
            for start, end in merged:
                parts.extend((text[cursor:start], _ENTITY_PLACEHOLDER))
                cursor = end
            parts.append(text[cursor:])
            return NerRedactionResult(
                text="".join(parts),
                confidence=max(0.0, min(1.0, min(confidences, default=0.0))),
            )
    except NerArtifactUnavailableError as exc:
        raise PseudonymisationUnavailableError(str(exc)) from exc
    except Exception as exc:
        raise PseudonymisationUnavailableError(
            f"NER inference failed for supported locale {locale}"
        ) from exc


def build_name_map(profile_names: list[str]) -> dict[str, str]:
    """Map each known profile name to a deterministic-per-session, random-across-sessions tag.

    A fresh secrets-based token per call means the SAME child is NOT re-linkable across two
    computations (sessions), while WITHIN one payload every mention of the name collapses to
    the same placeholder (so the model can still reason about "the same person").
    """
    name_map: dict[str, str] = {}
    for name in profile_names:
        if name and name not in name_map:
            token = secrets.token_hex(2).upper()
            name_map[name] = f"[PERSONA-{token}]"
    return name_map


def pseudonymise(
    *,
    payload: dict[str, Any],
    profile_names: list[str],
    locale: SupportedLocale,
    now_year: int,
    now_month: int,
) -> PseudonymisationResult:
    """Return a pseudonymised copy of ``payload`` safe to send to the AI client.

    CONTRACT (the security boundary):
      - Every string value (recursively in lists) is run through the redact transform.
      - ``tenant_id`` is STRIPPED entirely (never sent — Vertex routing is per-service-account).
      - ``source_up_ids`` remain only as an internal staging field. The external Vertex
        adapter replaces them with random per-request aliases before network I/O.
      - The caller supplies profile_names from the tenant record (decrypted display names);
        they are replaced FIRST.

    The input is never mutated; a new dict is returned.
    """
    manifest = load_ner_artifact_manifest()
    artifact = manifest.model_for(locale)
    name_map = build_name_map(profile_names)
    confidences: list[float] = []

    def _walk(value: Any) -> Any:
        if isinstance(value, str):
            redacted = _redact_text_field(
                value,
                name_map=name_map,
                locale=locale,
                now_year=now_year,
                now_month=now_month,
            )
            confidences.append(redacted.confidence)
            return redacted.text
        if isinstance(value, list):
            return [_walk(v) for v in value]
        if isinstance(value, dict):
            return {
                k: _walk(v)
                for k, v in value.items()
                if _canonical_key(k) not in _INTERNAL_IDENTIFIER_KEYS
            }
        return value

    clean: dict[str, Any] = {}
    for key, value in payload.items():
        # Hard strip: tenant_id never leaves our boundary.
        if _canonical_key(key) in _INTERNAL_IDENTIFIER_KEYS:
            continue
        # Preserve the internal staging list for server-side evidence mapping. The provider
        # adapter aliases every value before it constructs the external request.
        if key == "source_up_ids":
            clean[key] = [str(v) for v in value]
            continue
        clean[key] = _walk(value)
    from app.config.settings import settings

    identity = artifact.identity if settings.ai_ner_engine == "spacy" else "regex-dev-only"
    return PseudonymisationResult(
        payload=clean,
        locale=locale,
        artifact_manifest_version=manifest.manifest_version,
        artifact_identity=identity,
        confidence=min(confidences, default=1.0),
    )


def assert_no_tenant_id(payload: dict[str, Any]) -> None:
    """Defence-in-depth assertion rejecting tenant identifiers at any nesting level."""

    def _walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                if _canonical_key(key) == "tenantid":
                    raise ValueError(
                        "tenant_id must never be present in an AI payload (security boundary)."
                    )
                _walk(nested)
        elif isinstance(value, list):
            for nested in value:
                _walk(nested)

    _walk(payload)


def assert_no_internal_identifiers(payload: dict[str, Any]) -> None:
    """Reject direct IDs/contact data before an external provider call.

    Stable UP UUIDs are allowed only in the top-level ``source_up_ids`` staging field; the
    Vertex adapter must replace them with request-local aliases before constructing its prompt.
    """

    def _walk(value: Any, path: tuple[object, ...]) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                if _canonical_key(key) in _INTERNAL_IDENTIFIER_KEYS:
                    raise ValueError(
                        f"internal identifier key must not reach an AI provider: {key}"
                    )
                _walk(nested, (*path, key))
            return
        if isinstance(value, list):
            for index, nested in enumerate(value):
                _walk(nested, (*path, index))
            return
        source_id = len(path) == 2 and path[0] == "source_up_ids" and isinstance(path[1], int)
        if isinstance(value, UUID):
            if not source_id:
                raise ValueError("stable internal UUID must not reach an AI provider")
            return
        if not isinstance(value, str):
            return
        if _EMAIL_RE.search(value) or _PHONE_RE.search(value):
            raise ValueError("direct contact data must not reach an AI provider")
        if _UUID_RE.search(value) and not source_id:
            raise ValueError("stable internal UUID must not reach an AI provider")

    _walk(payload, ())


# Re-exported for tests that want to assert UUIDs are opaque.
def is_uuid_like(value: str) -> bool:
    try:
        UUID(value)
        return True
    except (ValueError, AttributeError, TypeError):
        return False
