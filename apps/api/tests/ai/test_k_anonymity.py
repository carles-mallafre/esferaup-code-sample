"""Plan 026 Step 4 — k-anonymity check before any AI call.

A sparse cohort (fewer than the threshold of comparable profiles) → False, which the pipeline
surfaces as 503 INSUFFICIENT_ANONYMITY_SET. A populous cohort → True.
"""

from __future__ import annotations

import pytest

from app.ai.k_anonymity import check_k_anonymity, cohort_size, compute_age_bucket
from tests.factories.profile import ProfileFactory

pytestmark = pytest.mark.asyncio


async def test_k_anonymity_sparse_cohort_blocks(family_ctx: dict) -> None:
    """A lone profile in its cohort → below threshold → False (→ 503 in the pipeline)."""
    db = family_ctx["db"]
    # family_ctx created exactly one child profile in this tenant; with the default
    # threshold of 5 and a near-empty test DB the cohort is sparse.
    ok = await check_k_anonymity(
        db, profile_id=family_ctx["profile_id"], tenant_id=family_ctx["tenant_id"]
    )
    assert ok is False


async def test_k_anonymity_populous_cohort_allows(family_ctx: dict, monkeypatch) -> None:
    """With the threshold lowered to 1, the existing profile's cohort passes."""
    from app.config import settings as settings_mod

    monkeypatch.setattr(settings_mod.settings, "ai_k_anonymity_threshold", 1)
    db = family_ctx["db"]
    ok = await check_k_anonymity(
        db, profile_id=family_ctx["profile_id"], tenant_id=family_ctx["tenant_id"]
    )
    assert ok is True


async def test_cohort_size_counts_comparable_profiles(family_ctx: dict) -> None:
    """Adding more minor profiles in the same-locale tenant grows the cohort count."""
    db = family_ctx["db"]
    base = await cohort_size(
        db, profile_id=family_ctx["profile_id"], tenant_id=family_ctx["tenant_id"]
    )
    # Add two more minor profiles in the same tenant (same locale → same cohort).
    for _ in range(2):
        await ProfileFactory(db, tenant_id=family_ctx["tenant_id"], lifecycle="minor")
    await db.flush()
    grown = await cohort_size(
        db, profile_id=family_ctx["profile_id"], tenant_id=family_ctx["tenant_id"]
    )
    assert grown >= base + 2


async def test_compute_age_bucket() -> None:
    """Age buckets map correctly (used when dob becomes available plaintext)."""
    from datetime import date

    today = date(2026, 6, 1)
    assert compute_age_bucket(date(2025, 1, 1), today=today) == "0-2"
    assert compute_age_bucket(date(2020, 1, 1), today=today) == "6-8"
    assert compute_age_bucket(date(2012, 1, 1), today=today) == "12-14"
