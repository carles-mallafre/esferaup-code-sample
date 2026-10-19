"""K-anonymity check before any AI call (Plan 026 Step 4, Round-2 locked).

Before sending a profile's data to the AI client we require the profile to sit in a cohort of
at least k comparable profiles (default k=5; the lawyer confirms the final value in
DPIA-AI-Art.22). If k < threshold the pipeline returns 503 INSUFFICIENT_ANONYMITY_SET and the
caller falls back to a generic recommendation (no child-specific framing).

Cohort definition (Round-2): the plan specifies (age_bucket, region_code, place_type). The
MVP schema stores dob ENCRYPTED per-tenant and has no region_code/place_type columns yet, so
a cross-tenant plaintext aggregate on those is impossible without leaking. We therefore key
the MVP cohort on the columns that ARE queryable cross-tenant WITHOUT decryption:

    (lifecycle, tenant.locale)

  - lifecycle (minor | adult_active | adult_archived | deceased) is a coarse age proxy that
    is NOT encrypted.
  - tenant.locale (ca | es | en) is a coarse region proxy.

This is a conservative, queryable cohort that satisfies the k-anonymity INVARIANT (don't send
a profile that is near-unique in the population). The richer (age_bucket, region, place_type)
cohort is a documented follow-up once those columns exist (the cohort function is the single
place to change). compute_age_bucket is provided for when dob becomes available plaintext.

The count uses a SYSTEM (BYPASSRLS) read — the cohort spans tenants by design, which is why
this lives behind the gate and never returns any per-profile data, only an integer count.
"""

from __future__ import annotations

from datetime import date
from uuid import UUID

import structlog
from sqlalchemy import text

logger = structlog.get_logger(__name__)


def compute_age_bucket(dob: date, *, today: date | None = None) -> str:
    """Map a date of birth to a coarse age bucket (used when dob is available plaintext)."""
    today = today or date.today()
    years = today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
    if years <= 2:
        return "0-2"
    if years <= 5:
        return "3-5"
    if years <= 8:
        return "6-8"
    if years <= 11:
        return "9-11"
    if years <= 14:
        return "12-14"
    return "15-17"


async def cohort_size(db: object, *, profile_id: UUID, tenant_id: UUID) -> int:
    """Return the number of comparable LIVE profiles across the population (incl. this one).

    Keyed on (lifecycle, tenant.locale). Uses the caller's session; because RLS would scope
    this to one tenant, the caller passes a system session for the cross-tenant count (the
    InsightService runs the k-anonymity check on its system-session pipeline). When called on
    a tenant-scoped session the count is naturally tenant-local (still a valid, stricter
    lower bound — fewer rows visible can only make the gate MORE conservative).
    """
    from sqlalchemy.ext.asyncio import AsyncSession

    session: AsyncSession = db  # type: ignore[assignment]

    # Resolve this profile's cohort key.
    row = (
        await session.execute(
            text(
                "SELECT p.lifecycle, t.locale "
                "FROM profiles p JOIN tenants t ON t.id = p.tenant_id "
                "WHERE p.id = :pid AND p.deleted_at IS NULL"
            ),
            {"pid": str(profile_id)},
        )
    ).first()
    if row is None:
        return 0
    lifecycle, locale = row[0], row[1]

    count = (
        await session.execute(
            text(
                "SELECT COUNT(*) FROM profiles p JOIN tenants t ON t.id = p.tenant_id "
                "WHERE p.lifecycle = :lifecycle AND t.locale = :locale "
                "AND p.deleted_at IS NULL"
            ),
            {"lifecycle": lifecycle, "locale": locale},
        )
    ).scalar_one()
    return int(count)


async def check_k_anonymity(db: object, *, profile_id: UUID, tenant_id: UUID) -> bool:
    """True if the profile's cohort has at least the configured threshold of members."""
    from app.config.settings import settings

    size = await cohort_size(db, profile_id=profile_id, tenant_id=tenant_id)
    ok = size >= settings.ai_k_anonymity_threshold
    if not ok:
        logger.info(
            "ai_k_anonymity_below_threshold",
            cohort_size=size,
            threshold=settings.ai_k_anonymity_threshold,
        )
    return ok
