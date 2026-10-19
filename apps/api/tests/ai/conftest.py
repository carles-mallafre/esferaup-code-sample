"""Fixtures for Plan 026 AI Patrons tests.

Reuses the family_ctx fixture (tenant + admin + child profile). Adds:
  - ai_client_stub: injects the LocalStubAiClient (the deterministic, hedged stand-in).
  - premium_sub(tenant_id): helper to insert an active premium subscription (the AI gate's
    premium check passes).
  - enable_ai_runtime(tenant_id): set the Redis ai:flag (the runtime gate; the DPIA feature
    flag is still off so endpoints 503 unless monkeypatched).
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.adapters.stub import LocalStubAiClient
from app.ai.client import _set_ai_client_for_testing
from tests.family.conftest import (  # noqa: F401
    auth_headers,
    family_ctx,
    mint_access_token,
    other_family,
)


@pytest_asyncio.fixture
async def ai_client_stub() -> AsyncGenerator[LocalStubAiClient]:
    """Inject the deterministic stub AI client; reset on teardown."""
    stub = LocalStubAiClient()
    _set_ai_client_for_testing(stub)
    try:
        yield stub
    finally:
        _set_ai_client_for_testing(None)


async def insert_premium_subscription(db: AsyncSession, tenant_id: uuid.UUID) -> None:
    """Insert an active premium subscription so the AI premium gate passes."""
    await db.execute(
        text(
            "INSERT INTO subscriptions (id, tenant_id, tier, status, provider, created_at) "
            "VALUES (:id, :tid, 'premium', 'active', 'stripe', now())"
        ),
        {"id": str(uuid.uuid4()), "tid": str(tenant_id)},
    )
    await db.flush()


async def grant_platform_staff(db: AsyncSession, user_id: uuid.UUID) -> None:
    """Add the user to the internal-admin allowlist (the /v1/internal/ai/* gate)."""
    await db.execute(
        text(
            "INSERT INTO platform_staff (user_id, role) VALUES (:uid, 'internal_admin') "
            "ON CONFLICT (user_id) DO NOTHING"
        ),
        {"uid": str(user_id)},
    )
    await db.flush()


async def enable_ai_runtime_flag(tenant_id: uuid.UUID) -> None:
    """Set the per-tenant runtime AI flag in Redis (the fail-closed gate's positive case)."""
    from app.ai.gate import set_tenant_ai_flag

    await set_tenant_ai_flag(tenant_id, enabled=True)
