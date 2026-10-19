"""Always-on deterministic Patró service (Plan 026)."""

from __future__ import annotations

import hashlib
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.heuristics.pattern_v1 import (
    HEURISTIC_VERSION,
    MAX_SUPPORTING_ENTRIES,
    build_pattern_candidate,
)
from app.audit.event_kinds import AuditEventKind
from app.audit.repository import AuditEventRepository
from app.audit.schemas import NewAuditEvent
from app.errors import AppError
from app.repositories.outbox_repository import OutboxRepository
from app.repositories.pattern_repository import PatternRepository


class PatternNotFoundError(AppError):
    def __init__(self) -> None:
        super().__init__(
            code="PATTERN_NOT_FOUND",
            status_code=404,
            message="Patró not found.",
        )


class PatternService:
    def __init__(self, db: AsyncSession) -> None:
        self._db = db
        self._patterns = PatternRepository(db)
        self._audit = AuditEventRepository(db)
        self._outbox = OutboxRepository(db)

    async def generate_profile(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        as_of: date,
    ) -> dict:
        """Reconcile one profile to exactly one current v1 candidate, if qualified."""
        current_week_start = as_of - timedelta(days=as_of.weekday())
        window_end = current_week_start + timedelta(days=7)
        window_start = window_end - timedelta(weeks=6)
        entries = await self._patterns.load_inputs(
            tenant_id,
            profile_id,
            window_start=window_start,
            window_end=window_end,
        )
        candidate = build_pattern_candidate(entries, as_of=as_of)
        now = datetime.now(UTC)
        if candidate is None:
            retired = await self._patterns.retire_other_candidates(
                tenant_id,
                profile_id,
                keep_factor_key=None,
                retired_at=now,
            )
            return {"status": "no_candidate", "changed": retired > 0, "pattern_id": None}

        pattern_id, upserted = await self._patterns.upsert_candidate(
            tenant_id,
            profile_id,
            candidate,
            generated_at=now,
        )
        retired = await self._patterns.retire_other_candidates(
            tenant_id,
            profile_id,
            keep_factor_key=candidate.factor_key,
            retired_at=now,
        )
        return {
            "status": "generated",
            "changed": upserted or retired > 0,
            "pattern_id": pattern_id,
        }

    async def list_patterns(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        limit: int,
        history_cutoff_at: datetime | None = None,
    ) -> list[dict]:
        return await self._patterns.list_visible(
            tenant_id,
            profile_id,
            limit=limit,
            generated_before=history_cutoff_at,
        )

    async def get_pattern(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        pattern_id: uuid.UUID,
        *,
        user_id: uuid.UUID,
        history_cutoff_at: datetime | None = None,
    ) -> dict:
        pattern = await self._patterns.get_detail(
            tenant_id,
            profile_id,
            pattern_id,
            generated_before=history_cutoff_at,
        )
        if pattern is None:
            raise PatternNotFoundError()

        references = pattern.get("supporting_entries") or []
        entry_ids: list[uuid.UUID] = []
        for reference in references[:MAX_SUPPORTING_ENTRIES]:
            if not isinstance(reference, dict) or reference.get("entity_type") != "up":
                continue
            try:
                entry_ids.append(uuid.UUID(str(reference["entity_id"])))
            except (KeyError, TypeError, ValueError):
                continue

        rows = await self._patterns.hydrate_supporting_ups(
            tenant_id,
            profile_id,
            entry_ids,
            occurred_before=history_cutoff_at,
        )
        hydrated: list[dict] = []
        for row in rows:
            note = await self._decrypt_note(tenant_id, row)
            category = str(row["category"])
            if category in {"salut", "emocions"}:
                from app.gdpr.special_category_log import SpecialCategoryAccessLogRepository

                await SpecialCategoryAccessLogRepository(self._db).append(
                    tenant_id=tenant_id,
                    resource_kind="up",
                    resource_id=uuid.UUID(str(row["id"])),
                    purpose="family_member_view",
                    user_id=user_id,
                )
            hydrated.append(
                {
                    "entity_id": row["id"],
                    "occurred_at": row["occurred_at"],
                    "factor_tag": category,
                    "note_excerpt": self._excerpt(note),
                }
            )

        pattern["supporting_entries"] = hydrated
        return pattern

    async def mute_pattern(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        pattern_id: uuid.UUID,
        *,
        actor_user_id: uuid.UUID,
    ) -> dict:
        pattern, changed = await self._patterns.set_muted(tenant_id, profile_id, pattern_id)
        if pattern is None:
            raise PatternNotFoundError()
        if not changed:
            return pattern

        profile_id_hash = hashlib.sha256(str(profile_id).encode("utf-8")).hexdigest()[:16]
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.PATTERN_MUTED,
                tenant_id=tenant_id,
                actor_user_id=actor_user_id,
                entity_type="pattern",
                entity_id=pattern_id,
                meta={"profile_id_hash": profile_id_hash},
            )
        )
        await self._outbox.insert_once(
            tenant_id,
            event_type="pattern.muted",
            payload={"profile_id": str(profile_id), "pattern_id": str(pattern_id)},
            idempotency_key=uuid.uuid5(pattern_id, "pattern.muted"),
        )
        await self._db.flush()
        return pattern

    async def _decrypt_note(self, tenant_id: uuid.UUID, row: dict) -> str | None:
        ciphertext = row.get("note_encrypted")
        if ciphertext is None:
            return row.get("note_plain")
        from app.encryption import decrypt_field_for_tenant

        plaintext = await decrypt_field_for_tenant(
            ciphertext=bytes(ciphertext),
            tenant_id=tenant_id,
            column_key="UP.note",
            row_id=uuid.UUID(str(row["id"])),
            db=self._db,
        )
        return plaintext.decode("utf-8")

    @staticmethod
    def _excerpt(note: str | None) -> str | None:
        if not note:
            return None
        compact = " ".join(note.split())
        return compact[:120] or None


__all__ = ["HEURISTIC_VERSION", "PatternNotFoundError", "PatternService"]
