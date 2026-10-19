"""Fixtures for Plan 019 UP + Crisi tests.

Reuses the family fixtures (family_ctx / other_family / mint_access_token /
auth_headers) from tests/family/conftest.py, then layers UP-specific helpers:
  - up_ctx: family_ctx + a granted 'ups' consent + the tenant context set so
    service-layer create_up calls pass the @requires_profile_consent('ups') gate.
  - grant_ups_consent(db, tenant_id, profile_id, user_id): insert a live consent.

All service-layer tests call UPService directly with db_session (SAVEPOINT rollback
per test). HTTP tests use the test_client fixture from the root conftest.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

# Re-export the family fixtures so tests/up/* can request them by name.
from tests.family.conftest import (  # noqa: F401
    auth_headers,
    family_ctx,
    mint_access_token,
    other_family,
    second_user,
)


async def grant_ups_consent(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    profile_id: uuid.UUID,
    user_id: uuid.UUID,
    *,
    scope: str = "ups",
) -> None:
    """Insert a live ProfileConsent row for `scope` (revoked_at NULL)."""
    from app.gdpr.consent import ConsentRepository

    await ConsentRepository(db).grant(
        tenant_id=tenant_id,
        profile_id=profile_id,
        granted_by_user_id=user_id,
        scope=scope,
        basis="parental_authority",
        policy_version="2026-05-01",
    )
    await db.flush()


async def revoke_ups_consent(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    profile_id: uuid.UUID,
    user_id: uuid.UUID,
    *,
    scope: str = "ups",
) -> None:
    """Revoke the live consent ProfileService grants at profile creation."""
    from app.gdpr.consent import ConsentRepository

    await ConsentRepository(db).revoke(
        tenant_id=tenant_id,
        profile_id=profile_id,
        revoked_by_user_id=user_id,
        scope=scope,
        policy_version="2026-05-01",
    )
    await db.flush()


@pytest_asyncio.fixture
async def up_ctx(db_session: AsyncSession, family_ctx: dict) -> AsyncGenerator[dict]:  # noqa: F811
    """family_ctx + a granted 'ups' consent. Tenant context is already set by
    family_ctx (admin/edit on the child profile)."""
    await grant_ups_consent(
        db_session, family_ctx["tenant_id"], family_ctx["profile_id"], family_ctx["admin_id"]
    )
    yield family_ctx
