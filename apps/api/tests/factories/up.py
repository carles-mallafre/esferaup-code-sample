"""UPFactory, UPCrisiFactory.

Aligned to the Option-H schema (Plan 010 / 0003): the UP note lives in EITHER
note_plain (non-Art-9) OR note_encrypted (Art-9) — never both (CHECK note_exactly_one).
By default the factory creates a NON-Art-9 ('casa') UP with note_plain so tests that
just need a UP row do not require KMS keys. Pass an Art-9 category with note_encrypted
explicitly to exercise the encrypted path.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.up import UP, UPCrisi

from .base import faker, generate_uuid, persist_to_db

_ART9 = {"salut", "emocions"}


async def UPFactory(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    profile_id: uuid.UUID,
    author_user_id: uuid.UUID,
    up_id: uuid.UUID | None = None,
    category: str | None = None,
    note_plain: str | None = None,
    note_encrypted: bytes | None = None,
    note_search_tokens: list | None = None,
    mood: str | None = None,
    is_crisi: bool = False,
    **kwargs: dict,
) -> UP:
    """Create a test UP (family-authored capture).

    Defaults to a non-Art-9 'casa' UP with a plaintext note. The CHECK constraints
    require exactly one of (note_plain, note_encrypted) non-null and forbid
    note_plain on Art-9 categories — the factory respects both.
    """
    up_id = up_id or generate_uuid()
    category = category or "casa"

    if note_encrypted is None and note_plain is None:
        if category in _ART9:
            # Art-9 categories cannot use note_plain; caller must pass note_encrypted.
            note_encrypted = b"\x00\x00\x00\x01" + b"x" * 40  # opaque non-empty ciphertext
        else:
            note_plain = f"Test note: {faker.sentence()}"

    up = UP(
        id=up_id,
        tenant_id=tenant_id,
        profile_id=profile_id,
        author_user_id=author_user_id,
        category=category,
        note_plain=note_plain,
        note_encrypted=note_encrypted,
        note_search_tokens=note_search_tokens if note_search_tokens is not None else [],
        mood=mood,
        is_crisi=is_crisi,
        occurred_at=datetime.now(UTC),
        **kwargs,
    )

    return await persist_to_db(up, db)


async def UPCrisiFactory(
    db: AsyncSession,
    up_id: uuid.UUID,
    trigger_text: bytes | None = None,
    resolution_text: bytes | None = None,
    **kwargs: dict,
) -> UPCrisi:
    """Create a test UPCrisi (sidecar of UP). trigger/resolution are encrypted bytea."""
    trigger_text = trigger_text or b"\x00\x00\x00\x01Test trigger"
    resolution_text = resolution_text or b"\x00\x00\x00\x01Test resolution"

    crisi = UPCrisi(
        up_id=up_id,
        trigger_text=trigger_text,
        resolution_text=resolution_text,
        duration_bucket="five_to_15",
        **kwargs,
    )

    return await persist_to_db(crisi, db)


__all__ = ["UPCrisiFactory", "UPFactory"]
