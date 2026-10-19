"""Live profile-role checks for UUID-keyed UP routes.

UP routes do not carry ``profile_id`` in their path, so authorization resolves the
owning profile from the tenant-scoped UP row. Missing rows and missing live
memberships deliberately share the same opaque error.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import AppError
from app.family.roles import role_satisfies
from app.family.temporal_access import ProfileTemporalState
from app.repositories.profile_temporal_access_repository import (
    ProfileTemporalAccessRepository,
)
from app.up.errors import UPNotFoundError


async def _assert_captured_within_scope(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    profile_id: uuid.UUID,
    *,
    authority_origin: str,
    captured_at: datetime,
) -> None:
    """Same predicate as ``app_profile_row_visible(profile_id, created_at)``, the
    restrictive policy on ``ups``: an inherited at-18 membership sees a UP only while
    its grant is current, or history-only with the UP captured at or before the cutoff.
    The grant is resolved for the session's bound actor, so an unbound session is denied.
    """
    if authority_origin == "ordinary":
        return
    scope = await ProfileTemporalAccessRepository(db).resolve_scope(tenant_id, profile_id)
    if scope is None:
        raise UPNotFoundError()
    state = ProfileTemporalState(str(scope["access_state"]))
    if state is ProfileTemporalState.CURRENT and scope["future_access_enabled"]:
        return
    if state is ProfileTemporalState.HISTORY_ONLY and captured_at <= scope["history_cutoff_at"]:
        return
    raise UPNotFoundError()


async def assert_up_role(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    user_id: uuid.UUID,
    up_id: uuid.UUID,
    minimum: str,
) -> uuid.UUID:
    row = (
        await db.execute(
            text(
                "SELECT u.profile_id, fm.role, fm.authority_origin, u.created_at "
                "FROM ups u "
                "LEFT JOIN family_memberships fm "
                "  ON fm.tenant_id = u.tenant_id "
                " AND fm.profile_id = u.profile_id "
                " AND fm.user_id = :uid AND fm.deleted_at IS NULL "
                "WHERE u.id = :up_id AND u.tenant_id = :tid "
                "AND u.deleted_at IS NULL"
            ),
            {"tid": str(tenant_id), "uid": str(user_id), "up_id": str(up_id)},
        )
    ).first()
    if row is None or row[0] is None:
        raise UPNotFoundError()
    profile_id = uuid.UUID(str(row[0]))
    # No membership: an adult who kept cross-family access when the profile moved to
    # its own family (ADR-026) reads it, view-only, within its grant.
    role, origin = (row[1], str(row[2])) if row[1] is not None else ("view_only", "cross_family")
    await _assert_captured_within_scope(
        db, tenant_id, profile_id, authority_origin=origin, captured_at=row[3]
    )
    if not role_satisfies(role, minimum):
        raise AppError(code="FORBIDDEN", status_code=403, message="Insufficient role.")
    return profile_id


async def assert_profile_role(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    user_id: uuid.UUID,
    profile_id: uuid.UUID,
    minimum: str,
    *,
    captured_at: datetime | None = None,
) -> None:
    """Same contract as ``assert_up_role`` when the profile is already known (a
    soft-deleted UP is invisible to that helper). ``captured_at`` is the ``created_at``
    of the UP being acted on, when there is one."""
    row = (
        await db.execute(
            text(
                "SELECT role, authority_origin FROM family_memberships "
                "WHERE tenant_id = :tid AND profile_id = :pid AND user_id = :uid "
                "AND deleted_at IS NULL"
            ),
            {"tid": str(tenant_id), "uid": str(user_id), "pid": str(profile_id)},
        )
    ).first()
    if row is None:
        raise UPNotFoundError()
    role = row[0]
    if captured_at is not None:
        await _assert_captured_within_scope(
            db, tenant_id, profile_id, authority_origin=str(row[1]), captured_at=captured_at
        )
    if not role_satisfies(role, minimum):
        raise AppError(code="FORBIDDEN", status_code=403, message="Insufficient role.")


__all__ = ["assert_profile_role", "assert_up_role"]
