"""UP + Crisi endpoints — Plan 019 (HTTP only; ALL logic in UPService).

  POST   /v1/profiles/{profile_id}/ups       — create a UP (+ optional Crisi sidecar)
  POST   /v1/profiles/{profile_id}/crisis     — convenience: forces is_crisi=True
  GET    /v1/ups/{up_id}                       — read (Art-9 access logged + decrypted)
  PATCH  /v1/ups/{up_id}                        — patch (is_crisi immutable)
  DELETE /v1/ups/{up_id}                        — soft-delete (7-day recovery)
  GET    /v1/ups/deleted?profile_id=            — the profile's recoverable UPs
  POST   /v1/ups/{up_id}/restore                — undo a delete inside the 7 days
  POST   /v1/ups/{up_id}/pin-memory             — idempotent pin
  POST   /v1/ups/{up_id}/unpin-memory           — idempotent unpin
  POST   /v1/ups/{up_id}/crisi/redact           — selective erasure of Crisi text

The write endpoints carry @requires_profile_role(edit) + @requires_profile_consent
('ups') (on the service) + require_profile_unlocked + Idempotency-Key. The Crisi
endpoint delegates to UPService.create_up (NO duplicate TX). Crisi error codes are
neutral / non-alarming (TRIGGER_REQUIRED, …) — the 'moment difícil' COPY is Plan 042.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_active_user
from app.api.permissions import (
    cross_family_up_reader,
    require_profile_unlocked,
    requires_profile_role,
)
from app.core.redis import get_redis
from app.core.tenant_context import get_tenant_id
from app.db.session import get_db
from app.family.roles import ProfileRole
from app.middleware.idempotency import IdempotencyContext, idempotency_guard
from app.models.tenant import User
from app.schemas.up import (
    CrisiCreateRequest,
    CrisiCreateResult,
    CrisiData,
    CrisiRedactRequest,
    DeletedUPListResponse,
    PinResult,
    UPAttachmentDownloadResponse,
    UPCreateRequest,
    UPCreateResult,
    UPPatchRequest,
    UPResponse,
    UPRestoreResult,
)
from app.services.home_cache import invalidate_home_cache
from app.services.up_service import UPService


async def _bust_home_cache(profile_id: uuid.UUID) -> None:
    """Post-commit cache invalidation (Plan 020 contract). Own Redis client,
    closed after use; swallows errors (never fails a committed write)."""
    redis = get_redis()
    try:
        await invalidate_home_cache(redis, profile_id)
    finally:
        await redis.aclose()


ups_router = APIRouter(prefix="/v1/profiles", tags=["ups"])
up_router = APIRouter(prefix="/v1/ups", tags=["ups"])


# ── create (profile-scoped) ──────────────────────────────────────────────────


@ups_router.post("/{profile_id}/ups", status_code=201, response_model=UPCreateResult)
async def create_up(
    profile_id: uuid.UUID,
    body: UPCreateRequest,
    current_user: User = Depends(get_current_active_user),
    _role: None = requires_profile_role(ProfileRole.EDIT.value),
    _unlocked: None = Depends(require_profile_unlocked),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> UPCreateResult:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    result = await service.create_up(tenant_id, profile_id, current_user.id, body)
    out = UPCreateResult(
        id=result.id,
        punts_awarded=result.punts_awarded,
        daily_cap_reached=result.daily_cap_reached,
        esfera_counts=result.esfera_counts,
    )
    await idem.record_response(201, out.model_dump(mode="json"))
    await _bust_home_cache(profile_id)
    return out


@ups_router.post("/{profile_id}/crisis", status_code=201, response_model=CrisiCreateResult)
async def create_crisi(
    profile_id: uuid.UUID,
    body: CrisiCreateRequest,
    current_user: User = Depends(get_current_active_user),
    _role: None = requires_profile_role(ProfileRole.EDIT.value),
    _unlocked: None = Depends(require_profile_unlocked),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> CrisiCreateResult:
    """Convenience endpoint for the dedicated difficult-moment form. Forces
    is_crisi=True and delegates to the SAME create_up TX (no duplication)."""
    tenant_id = get_tenant_id()
    up_create = UPCreateRequest(
        category=body.category,
        occurred_at=body.occurred_at,
        note=body.note,
        is_crisi=True,
        crisi=CrisiData(
            trigger_text=body.trigger_text,
            resolution_text=body.resolution_text,
            duration_bucket=body.duration_bucket,
            mood_after=body.mood_after,
            draft=body.draft,
        ),
        save_to_arxiu=body.save_to_arxiu,
        arxiu_section=body.arxiu_section,
    )
    service = UPService.from_session(db)
    result = await service.create_up(tenant_id, profile_id, current_user.id, up_create)
    out = CrisiCreateResult(
        id=result.id,
        up_id=result.id,
        punts_awarded=result.punts_awarded,
        daily_cap_reached=result.daily_cap_reached,
        esfera_counts=result.esfera_counts,
    )
    await idem.record_response(201, out.model_dump(mode="json"))
    await _bust_home_cache(profile_id)
    return out


# ── single-UP read / patch / delete ──────────────────────────────────────────


# Declared before "/{up_id}" so "deleted" is not parsed as a UP id.
@up_router.get("/deleted", response_model=DeletedUPListResponse)
async def list_deleted_ups(
    response: Response,
    profile_id: uuid.UUID = Query(...),
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
) -> DeletedUPListResponse:
    """UPs of one profile deleted in the last 7 days, with the days left to restore
    each. Needs the edit role (the one that can delete and restore)."""
    tenant_id = get_tenant_id()
    items = await UPService.from_session(db).list_deleted_ups(
        tenant_id, profile_id, current_user.id
    )
    # Art-9 previews write an access-log row that must be persisted.
    await db.commit()
    response.headers["Cache-Control"] = "private, no-store"
    return DeletedUPListResponse(items=items)


@up_router.get("/{up_id}", response_model=UPResponse)
async def get_up(
    up_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    _cross_family: None = Depends(cross_family_up_reader),
    db: AsyncSession = Depends(get_db),
) -> UPResponse:
    """Read a single UP. The service resolves the owning profile and requires a
    live view-only membership; Art-9 reads write a special-category access log."""
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    data = await service.get_up_decrypted(tenant_id, up_id, user_id=current_user.id)
    # The access-log write (for Art-9 reads) must be persisted.
    await db.commit()
    return UPResponse(**data)


@up_router.get(
    "/{up_id}/attachments/{attachment_index}/download",
    response_model=UPAttachmentDownloadResponse,
)
async def create_up_attachment_download(
    up_id: uuid.UUID,
    attachment_index: int,
    response: Response,
    current_user: User = Depends(get_current_active_user),
    _cross_family: None = Depends(cross_family_up_reader),
    db: AsyncSession = Depends(get_db),
) -> UPAttachmentDownloadResponse:
    """Mint a 60-second read URL after membership and scan checks."""
    tenant_id = get_tenant_id()
    out = await UPService.from_session(db).create_attachment_download_grant(
        tenant_id,
        up_id,
        attachment_index,
        user_id=current_user.id,
    )
    await db.commit()
    response.headers["Cache-Control"] = "private, no-store"
    return UPAttachmentDownloadResponse(**out)


@up_router.patch("/{up_id}", response_model=UPResponse)
async def patch_up(
    up_id: uuid.UUID,
    body: UPPatchRequest,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> UPResponse:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    data = await service.patch_up(tenant_id, up_id, current_user.id, body)
    out = UPResponse(**data)
    await idem.record_response(200, out.model_dump(mode="json"), cache_body=False)
    await _bust_home_cache(data["profile_id"])
    return out


@up_router.delete("/{up_id}", status_code=204)
async def delete_up(
    up_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> None:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    profile_id = await service.delete_up(tenant_id, up_id, current_user.id)
    await idem.record_response(204, {"ok": True})
    await _bust_home_cache(profile_id)


@up_router.post("/{up_id}/restore", response_model=UPRestoreResult)
async def restore_up(
    up_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> UPRestoreResult:
    tenant_id = get_tenant_id()
    data = await UPService.from_session(db).restore_up(tenant_id, up_id, current_user.id)
    out = UPRestoreResult(**data)
    await idem.record_response(200, out.model_dump(mode="json"))
    await _bust_home_cache(data["profile_id"])
    return out


# ── pin / unpin / redact ─────────────────────────────────────────────────────


@up_router.post("/{up_id}/pin-memory", response_model=PinResult)
async def pin_memory(
    up_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> PinResult:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    data = await service.pin_memory(tenant_id, up_id, current_user.id)
    out = PinResult(is_pinned=data["is_pinned"], was_already=data["was_already"])
    await idem.record_response(200, out.model_dump(mode="json"))
    await _bust_home_cache(data["profile_id"])
    return out


@up_router.post("/{up_id}/unpin-memory", response_model=PinResult)
async def unpin_memory(
    up_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> PinResult:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    data = await service.unpin_memory(tenant_id, up_id, current_user.id)
    out = PinResult(is_pinned=data["is_pinned"], was_already=data["was_already"])
    await idem.record_response(200, out.model_dump(mode="json"))
    await _bust_home_cache(data["profile_id"])
    return out


@up_router.post("/{up_id}/crisi/redact", status_code=200)
async def redact_crisi(
    up_id: uuid.UUID,
    body: CrisiRedactRequest,
    current_user: User = Depends(get_current_active_user),
    idem: IdempotencyContext = Depends(idempotency_guard),
    db: AsyncSession = Depends(get_db),
) -> dict:
    tenant_id = get_tenant_id()
    service = UPService.from_session(db)
    await service.redact_crisi(
        tenant_id, up_id, current_user.id, reclassified_as=body.reclassified_as
    )
    out = {"redacted": True}
    await idem.record_response(200, out)
    return out
