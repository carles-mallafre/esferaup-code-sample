"""Deterministic six-week Patró rubric (Plan 026).

This module is intentionally pure: no database, Redis, feature-flag, consent, or model
provider calls. Given the same bounded UP metadata and ``as_of`` date it returns the same
candidate and fingerprint. It never reads note text.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections import Counter
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Final

from app.ai.voice_lock import find_forbidden, has_required_hedge

HEURISTIC_VERSION: Final = "pattern_v1"
WEEKS_WINDOW: Final = 6
MAX_SUPPORTING_ENTRIES: Final = 10
MIN_TOTAL_ENTRIES: Final = 6
MIN_ACTIVE_WEEKS: Final = 3
MIN_FACTOR_ENTRIES: Final = 3
MIN_FACTOR_WEEKS: Final = 2

_CATEGORY_ORDER: Final = (
    "casa",
    "escola",
    "emocions",
    "esport",
    "salut",
    "nutricio",
    "descans",
    "activa",
)

_LABELS: Final[dict[str, tuple[str, str, str]]] = {
    "casa": ("Casa", "Casa", "Home"),
    "escola": ("Escola", "Escuela", "School"),
    "emocions": ("Emocions", "Emociones", "Emotions"),
    "esport": ("Esport", "Deporte", "Sport"),
    "salut": ("Salut", "Salud", "Health"),
    "nutricio": ("Nutrició", "Nutrición", "Nutrition"),
    "descans": ("Descans", "Descanso", "Rest"),
    "activa": ("Activa", "Activa", "Activa"),
}


@dataclass(frozen=True, slots=True)
class PatternInput:
    entity_id: uuid.UUID
    category: str
    occurred_at: datetime


@dataclass(frozen=True, slots=True)
class PatternCandidate:
    factor_key: str
    factor_label_ca: str
    factor_label_es: str
    factor_label_en: str
    statement_ca: str
    statement_es: str
    statement_en: str
    confidence: float
    weeks_window: int
    paired_series: list[dict[str, str | int]]
    supporting_entries: list[dict[str, str]]
    chart_summary_ca: str
    chart_summary_es: str
    chart_summary_en: str
    generation_fingerprint: str


def _week_start(value: date) -> date:
    return value - timedelta(days=value.weekday())


def _local_decimal(value: float) -> str:
    return f"{value:.1f}".replace(".", ",")


def build_pattern_candidate(
    entries: list[PatternInput],
    *,
    as_of: date,
) -> PatternCandidate | None:
    """Return the strongest qualifying category pattern for a six-week window.

    Qualification is deliberately conservative and factual: at least six UPs across
    three weeks, with the selected category represented by at least three UPs in two
    different weeks. Ties use the locked category order, never database row order.
    """

    window_end = _week_start(as_of) + timedelta(days=7)
    window_start = window_end - timedelta(weeks=WEEKS_WINDOW)
    bounded = sorted(
        (
            entry
            for entry in entries
            if entry.category in _LABELS
            and window_start <= entry.occurred_at.astimezone(UTC).date() < window_end
        ),
        key=lambda entry: (entry.occurred_at, str(entry.entity_id)),
    )
    if len(bounded) < MIN_TOTAL_ENTRIES:
        return None

    active_weeks = {_week_start(entry.occurred_at.astimezone(UTC).date()) for entry in bounded}
    if len(active_weeks) < MIN_ACTIVE_WEEKS:
        return None

    counts = Counter(entry.category for entry in bounded)
    category_rank = {category: index for index, category in enumerate(_CATEGORY_ORDER)}
    factor_key = min(
        counts,
        key=lambda category: (-counts[category], category_rank.get(category, 999)),
    )
    factor_entries = [entry for entry in bounded if entry.category == factor_key]
    factor_weeks = {
        _week_start(entry.occurred_at.astimezone(UTC).date()) for entry in factor_entries
    }
    if len(factor_entries) < MIN_FACTOR_ENTRIES or len(factor_weeks) < MIN_FACTOR_WEEKS:
        return None

    labels = _LABELS[factor_key]
    series: list[dict[str, str | int]] = []
    for offset in range(WEEKS_WINDOW):
        start = window_start + timedelta(weeks=offset)
        stop = start + timedelta(days=7)
        week_entries = [
            entry for entry in bounded if start <= entry.occurred_at.astimezone(UTC).date() < stop
        ]
        series.append(
            {
                "week_start": start.isoformat(),
                "with_factor": sum(entry.category == factor_key for entry in week_entries),
                "without_factor": sum(entry.category != factor_key for entry in week_entries),
            }
        )

    coverage = len(factor_weeks) / WEEKS_WINDOW
    share = len(factor_entries) / len(bounded)
    confidence = round(min(0.95, 0.50 + (0.25 * coverage) + (0.25 * share)), 2)

    statement_ca = (
        f"Sembla que l'esfera {labels[0].lower()} apareix amb regularitat en els UP recents."
    )
    statement_es = (
        f"Parece que la esfera {labels[1].lower()} aparece con regularidad en los UP recientes."
    )
    statement_en = f"The {labels[2].lower()} sphere may be appearing regularly in recent UPs."
    surfaced_copy = "\n".join((statement_ca, statement_es, statement_en))
    if (
        find_forbidden(surfaced_copy)
        or not has_required_hedge(statement_ca, "ca")
        or not has_required_hedge(statement_es, "es")
    ):
        raise RuntimeError("Heuristic Patró copy failed the voice lock")

    with_average = len(factor_entries) / WEEKS_WINDOW
    without_average = (len(bounded) - len(factor_entries)) / WEEKS_WINDOW
    chart_summary_ca = (
        f"Amb {labels[0].lower()}: {_local_decimal(with_average)} UP/setmana. "
        f"Sense {labels[0].lower()}: {_local_decimal(without_average)} UP/setmana. "
        f"{WEEKS_WINDOW} setmanes comparades."
    )
    chart_summary_es = (
        f"Con {labels[1].lower()}: {_local_decimal(with_average)} UP por semana. "
        f"Sin {labels[1].lower()}: {_local_decimal(without_average)} UP por semana. "
        f"{WEEKS_WINDOW} semanas comparadas."
    )
    chart_summary_en = (
        f"With {labels[2].lower()}: {with_average:.1f} UP per week. "
        f"Without {labels[2].lower()}: {without_average:.1f} UP per week. "
        f"{WEEKS_WINDOW} weeks compared."
    )

    recent_support = sorted(
        factor_entries,
        key=lambda entry: (entry.occurred_at, str(entry.entity_id)),
        reverse=True,
    )[:MAX_SUPPORTING_ENTRIES]
    supporting_entries = [
        {"entity_type": "up", "entity_id": str(entry.entity_id)} for entry in recent_support
    ]
    fingerprint_payload = {
        "as_of_week": window_end.isoformat(),
        "entries": [
            {
                "id": str(entry.entity_id),
                "category": entry.category,
                "occurred_at": entry.occurred_at.astimezone(UTC).isoformat(),
            }
            for entry in bounded
        ],
        "version": HEURISTIC_VERSION,
    }
    fingerprint = hashlib.sha256(
        json.dumps(fingerprint_payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()

    return PatternCandidate(
        factor_key=factor_key,
        factor_label_ca=labels[0],
        factor_label_es=labels[1],
        factor_label_en=labels[2],
        statement_ca=statement_ca,
        statement_es=statement_es,
        statement_en=statement_en,
        confidence=confidence,
        weeks_window=WEEKS_WINDOW,
        paired_series=series,
        supporting_entries=supporting_entries,
        chart_summary_ca=chart_summary_ca,
        chart_summary_es=chart_summary_es,
        chart_summary_en=chart_summary_en,
        generation_fingerprint=fingerprint,
    )


__all__ = [
    "HEURISTIC_VERSION",
    "MAX_SUPPORTING_ENTRIES",
    "PatternCandidate",
    "PatternInput",
    "build_pattern_candidate",
]
