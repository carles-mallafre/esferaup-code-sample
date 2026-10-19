"""Synthetic golden fixtures for the voice-lock eval harness (Plan 026 Step 9). EUPL-1.2.

NO PII — every payload is synthetic. Two fixture sets:
  - GOLDEN_INPUTS: pseudonymised input payloads fed to the LocalStubAiClient; the harness
    asserts the stub's output passes the two-sided voice-lock guard + schema + language.
  - NEURODIVERGENT_INPUTS: 10 baseline fixtures (the engine SUPPRESSES these in the service,
    but the prompt/output shape is still eval'd here for completeness).
  - BAD_OUTPUTS / GOOD_OUTPUTS: hand-written output strings proving the DETECTOR itself catches
    forbidden phrases + missing hedges (the eval's own test-of-the-test).

The real 50+10 golden set + the 30-day shadow-eval capture for the published validation study
are Plan 080/082; this MVP set exercises the harness end-to-end against the deterministic stub.
"""

from __future__ import annotations

# Input payloads (already pseudonymised — placeholders, no real names). Each is a valid
# weekly/outburst summary the stub turns into a hedged, voice-lock-compliant insight.
GOLDEN_INPUTS: list[dict] = [
    {
        "prompt_id": "insight_family_weekly",
        "weekly_summary": "descans: 3, casa: 2",
        "active_spheres": "casa, descans",
    },
    {
        "prompt_id": "insight_family_weekly",
        "weekly_summary": "escola: 4",
        "active_spheres": "escola",
    },
    {
        "prompt_id": "insight_family_weekly",
        "weekly_summary": "esport: 1, nutricio: 2",
        "active_spheres": "esport, nutricio",
    },
    {
        "prompt_id": "insight_outburst_tip",
        "weekly_summary": "moment de tensió a la tarda",
        "active_spheres": "emocions",
    },
    {
        "prompt_id": "insight_outburst_tip",
        "weekly_summary": "transició difícil abans de dormir",
        "active_spheres": "descans",
    },
]

NEURODIVERGENT_INPUTS: list[dict] = [
    {
        "prompt_id": "insight_outburst_tip",
        "weekly_summary": "rutina alterada",
        "active_spheres": "emocions",
        "baseline": "tea",
    },
    {
        "prompt_id": "insight_family_weekly",
        "weekly_summary": "descans: 2",
        "active_spheres": "descans",
        "baseline": "tdah",
    },
]

# Detector test-of-the-test: these MUST be caught (forbidden) / flagged (missing hedge).
BAD_OUTPUTS_FORBIDDEN: list[str] = [
    "Aquest és un diagnòstic clar de TDAH.",  # 'diagnostic' (ca)
    "Esto es un diagnóstico de dislexia.",  # 'diagnóstico' (es)
    "Has mantingut una ratxa de 5 dies! 🔥",  # 'ratxa' + 🔥
    "¡Llevas una racha increíble!",  # 'racha' (es)
    "Welcome to EsferaCreix, your streak is 7.",  # old brand + 'streak'
]

# A non-hedged but otherwise clean pair (the two-sided guard must flag missing hedges).
NON_HEDGED_CA = "Aquesta setmana hi ha hagut tres registres de descans."
NON_HEDGED_ES = "Esta semana ha habido tres registros de descanso."
