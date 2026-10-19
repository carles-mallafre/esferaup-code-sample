"""InsightService — the AI Patrons pipeline orchestrator (Plan 026 Steps 5-7, 9, 12, 15).

The full pipeline (every step is a gate; failing any returns the right error, never raw PII):

  gate (DPIA + fail-closed Redis flag) → premium → consent → build payload from the SHARED
  ups/profiles tables (raw SQL, NO app.up import — domain isolation) → PSEUDONYMISE (the
  security boundary) → k-anonymity (k>=5 else 503 INSUFFICIENT_ANONYMITY_SET) → cost breaker
  (pre-flight charge; hard ceiling auto-flips the flag) → AIClient.generate_insight →
  validate against InsightResponse (retry ONCE; on 2nd fail → null + AI_INSIGHT_VALIDATION_FAILED)
  → voice-lock guard (0 forbidden + hedged both langs) → FK-validate source_up_ids →
  encrypt body AES-256-GCM per-tenant DEK (Plan 013) → persist Insight → SWR cache.

SWR read (get_insight): Redis hit → return; Redis miss → DB live row → populate + return; DB
miss → synchronous compute (8s budget) → return or null. AI_INSIGHT_PRESENTED audited on read;
special_category_access_log on the Art-9 UP inputs.

particularity_baseline (Plan 026 Step 14): if set (tea/tdah/dyslexia/other) the engine SUPPRESSES
pattern-frequency insights (returns null) unless a neurodivergent rubric prompt is configured —
the MVP suppresses (co-authoring the neurodivergent rubric with a TEA clinician is deferred).

OBSERVABILITY (Step 10): ai.insight.computed logs HASHES + metadata ONLY — never prompt
content, raw response, UP text, profile name, or tenant_id.

DOMAIN ISOLATION: this module reads the shared ups + profiles tables by raw SQL (the SQL layer
is shared infra, like feed_entries) and NEVER imports app.up / app.document / app.observation.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from datetime import UTC, datetime, timedelta
from typing import cast

import structlog
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.gate import AiPipelineError, InsufficientAnonymitySetError
from app.ai.ner_artifacts import SupportedLocale
from app.ai.schema import (
    INSIGHT_RESPONSE_SCHEMA,
    InsightResponse,
    insight_cache_key,
    insight_hash,
)
from app.audit.event_kinds import AuditEventKind
from app.audit.repository import AuditEventRepository
from app.audit.schemas import NewAuditEvent

logger = structlog.get_logger(__name__)

_SWR_TTL_SECONDS = 60 * 60 * 12  # 12h SWR window
_DB_FRESHNESS = timedelta(hours=24)
_SUPPRESSING_BASELINES = {"tea", "tdah", "dyslexia", "other"}


class InsightService:
    """Compute + serve AI insights. Wraps a tenant-scoped session (RLS-protected insights)."""

    def __init__(self, db: AsyncSession) -> None:
        self._db = db
        self._audit = AuditEventRepository(db)

    # ── public read (SWR) ────────────────────────────────────────────────────────

    async def get_or_compute(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        prompt_id: str,
        actor_user_id: uuid.UUID,
    ) -> dict | None:
        """SWR read: Redis → DB(live, <24h) → synchronous compute. Returns the decrypted
        insight dict or None. Audits AI_INSIGHT_PRESENTED on a served insight."""
        from app.ai.prompts import active_prompt_version

        prompt_version = await active_prompt_version(prompt_id, db=self._db)
        key = insight_cache_key(
            tenant_id=tenant_id,
            profile_id=profile_id,
            prompt_id=prompt_id,
            prompt_version=prompt_version,
        )

        cached = await self._cache_get(key)
        if cached is not None:
            await self._audit_presented(tenant_id, profile_id, actor_user_id, cached.get("id"))
            return cached

        db_row = await self._fresh_db_insight(tenant_id, profile_id, prompt_id, prompt_version)
        if db_row is not None:
            await self._cache_set(key, db_row)
            await self._audit_presented(tenant_id, profile_id, actor_user_id, db_row.get("id"))
            return db_row

        # DB miss → synchronous compute (the 8s Vertex budget is a real-Vertex concern; the
        # stub is instant). On any failure the pipeline raises the right 503 / returns null.
        computed = await self.compute(
            tenant_id, profile_id, prompt_id=prompt_id, prompt_version=prompt_version
        )
        if computed is not None:
            await self._cache_set(key, computed)
            await self._audit_presented(tenant_id, profile_id, actor_user_id, computed.get("id"))
        return computed

    # ── compute pipeline ───────────────────────────────────────────────────────

    async def compute(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        *,
        prompt_id: str,
        prompt_version: str,
    ) -> dict | None:
        """Run the full pipeline. Returns the decrypted insight dict, or None (validation
        failed / neurodivergent suppression). Raises 503 for k-anonymity / pipeline errors."""
        from app.ai.cost_breaker import check_and_charge, estimate_tokens
        from app.ai.k_anonymity import check_k_anonymity
        from app.ai.prompts import get_prompt_for_version
        from app.ai.pseudonymise import assert_no_tenant_id, pseudonymise

        # Neurodivergent suppression (Step 14): suppress pattern-frequency insights when a
        # baseline is set (the neurodivergent rubric prompt is deferred until a clinician reviews it).
        if await self._particularity_baseline(tenant_id, profile_id) in _SUPPRESSING_BASELINES:
            logger.info("ai_insight_suppressed_particularity_baseline")
            return None

        # Build the raw payload from the SHARED ups/profiles tables (raw SQL, no app.up import).
        source_up_ids, weekly_summary = await self._collect_recent_ups(tenant_id, profile_id)
        active_spheres = await self._active_spheres(tenant_id, profile_id)
        locale = await self._tenant_locale(tenant_id)

        # Log the Art-9 UP inputs to the special-category access log.
        await self._log_art9_inputs(tenant_id, source_up_ids)

        raw_payload = {
            "source_up_ids": [str(u) for u in source_up_ids],
            "weekly_summary": weekly_summary,
            "active_spheres": active_spheres,
        }

        # THE SECURITY BOUNDARY: pseudonymise BEFORE the AI client; strip tenant_id.
        now = datetime.now(UTC)
        pseudonymisation = pseudonymise(
            payload=raw_payload,
            # V1 reads category counts and enum slugs only. It deliberately never decrypts a
            # profile name or UP note, so no direct child text enters this process boundary.
            profile_names=[],
            locale=locale,
            now_year=now.year,
            now_month=now.month,
        )
        clean_payload = pseudonymisation.payload
        assert_no_tenant_id(clean_payload)
        if pseudonymisation.catalan_confidence_requires_skip:
            await self._record_low_confidence_skip(
                confidence=pseudonymisation.confidence,
                artifact_manifest_version=pseudonymisation.artifact_manifest_version,
            )
            return None

        # K-anonymity (k>=5 else 503 + generic fallback handled by the router).
        if not await check_k_anonymity(self._db, profile_id=profile_id, tenant_id=tenant_id):
            raise InsufficientAnonymitySetError()

        # Cost breaker pre-flight (charge BEFORE the call; hard ceiling auto-flips the flag).
        est_in = estimate_tokens(clean_payload)
        if not await check_and_charge(self._db, tenant_id=tenant_id, estimated_input_tokens=est_in):
            raise AiPipelineError("AI temporarily paused (budget protection).")

        # Build the system+user prompt for the client (the stub ignores text content but the
        # real Vertex client uses it). prompt is validated (clinical_advisor_reviewed) on load.
        prompt = await get_prompt_for_version(self._db, prompt_id, prompt_version)
        client_payload = dict(clean_payload)
        client_payload["system_prompt"] = prompt.system_prompt
        client_payload["user_message"] = prompt.user_template.format(
            weekly_summary=clean_payload.get("weekly_summary", ""),
            active_spheres=clean_payload.get("active_spheres", ""),
            context_summary=clean_payload.get("weekly_summary", ""),
        )

        validated = await self._generate_with_retry(
            tenant_id=tenant_id,
            profile_id=profile_id,
            prompt_id=prompt_id,
            prompt_version=prompt_version,
            client_payload=client_payload,
            source_up_ids=source_up_ids,
            est_in=est_in,
        )
        if validated is None:
            return None

        # FK-validate source_up_ids against the ups table (service-side check, not a DB FK).
        validated_up_ids = await self._fk_filter_up_ids(tenant_id, validated.source_up_ids)

        # Persist (encrypt body) + return the decrypted dict.
        return await self._persist(
            tenant_id, profile_id, validated, validated_up_ids, prompt_id, prompt_version
        )

    async def _generate_with_retry(
        self,
        *,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        prompt_id: str,
        prompt_version: str,
        client_payload: dict,
        source_up_ids: list[uuid.UUID],
        est_in: int,
    ) -> InsightResponse | None:
        """Call the AIClient, validate against InsightResponse, retry ONCE, then null + audit."""
        from app.ai.client import get_ai_client
        from app.ai.voice_lock import find_forbidden, missing_required_hedges

        client = get_ai_client()
        last_error: str | None = None
        for attempt in (1, 2):
            try:
                raw = await client.generate_insight(
                    prompt_id=prompt_id,
                    prompt_version=prompt_version,
                    user_payload=client_payload,
                    response_schema=INSIGHT_RESPONSE_SCHEMA,
                )
            except Exception as exc:
                logger.warning("ai_client_call_failed", attempt=attempt, error=type(exc).__name__)
                raise AiPipelineError() from exc

            # Ensure prompt provenance is echoed (the stub does; defend for real models).
            raw.setdefault("prompt_id", prompt_id)
            raw.setdefault("prompt_version", prompt_version)
            try:
                validated = InsightResponse.model_validate(raw)
            except ValidationError as exc:
                last_error = "schema"
                logger.warning(
                    "ai_insight_validation_failed", attempt=attempt, errors=exc.error_count()
                )
                continue

            # Two-sided voice-lock guard: 0 forbidden + hedged in both languages.
            full = (
                f"{validated.title_ca}\n{validated.title_es}\n"
                f"{validated.body_ca}\n{validated.body_es}"
            )
            if find_forbidden(full) or missing_required_hedges(
                validated.body_ca, validated.body_es
            ):
                last_error = "voice_lock"
                logger.warning("ai_insight_voice_lock_failed", attempt=attempt)
                continue

            # Observability: hashes + metadata ONLY (no content, no name, no tenant_id).
            self._log_computed(
                prompt_id, prompt_version, client_payload, profile_id, est_in, validated
            )
            return validated

        # Both attempts failed validation/voice-lock → null + audit.
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.AI_INSIGHT_VALIDATION_FAILED,
                tenant_id=tenant_id,
                entity_type="profile",
                entity_id=profile_id,
                meta={
                    "prompt_id": prompt_id,
                    "prompt_version": prompt_version,
                    "reason": last_error,
                },
            )
        )
        await self._db.flush()
        return None

    # ── persistence (encrypt body) ───────────────────────────────────────────────

    async def _persist(
        self,
        tenant_id: uuid.UUID,
        profile_id: uuid.UUID,
        validated: InsightResponse,
        source_up_ids: list[uuid.UUID],
        prompt_id: str,
        prompt_version: str,
    ) -> dict:
        """Encrypt the structured body (titles+bodies ca/es as JSON) into
        insights.body_encrypted with the per-tenant DEK (Plan 013), persist the row + up-links,
        return the decrypted dict."""
        from app.encryption import encrypt_field_for_tenant

        insight_id = uuid.uuid4()
        ihash = insight_hash(
            prompt_id=prompt_id, prompt_version=prompt_version, source_up_ids=source_up_ids
        )
        body_blob = json.dumps(
            {
                "title_ca": validated.title_ca,
                "title_es": validated.title_es,
                "body_ca": validated.body_ca,
                "body_es": validated.body_es,
            },
            ensure_ascii=False,
        ).encode("utf-8")

        ciphertext = await encrypt_field_for_tenant(
            plaintext=body_blob,
            tenant_id=tenant_id,
            column_key="Insight.body",
            row_id=insight_id,
            db=self._db,
        )

        confidence_score = {"low": 0.3, "medium": 0.6, "high": 0.9}[validated.confidence_band]
        await self._db.execute(
            text(
                "INSERT INTO insights (id, tenant_id, profile_id, kind, body_encrypted, "
                "confidence_score, confidence_band, disclaimer_required, model_version, "
                "prompt_version, prompt_id, insight_hash, model_provenance, state, generated_at, "
                "published_at) VALUES (:id, :tid, :pid, :kind, :body, :cs, :cb, :dr, :mv, :pv, "
                ":pid_str, :hash, cast(:prov as jsonb), 'published', now(), now())"
            ),
            {
                "id": str(insight_id),
                "tid": str(tenant_id),
                "pid": str(profile_id),
                "kind": validated.kind.value,
                "body": ciphertext,
                "cs": confidence_score,
                "cb": validated.confidence_band,
                "dr": validated.disclaimer_required,
                "mv": validated.model_version or "stub",
                "pv": prompt_version,
                "pid_str": prompt_id,
                "hash": ihash,
                "prov": json.dumps({"model_id": validated.model_id or "stub-ai"}),
            },
        )
        for up_id in source_up_ids:
            await self._db.execute(
                text(
                    "INSERT INTO insight_up_links (insight_id, up_id) VALUES (:iid, :uid) "
                    "ON CONFLICT DO NOTHING"
                ),
                {"iid": str(insight_id), "uid": str(up_id)},
            )
        await self._db.flush()

        return {
            "id": str(insight_id),
            "kind": validated.kind.value,
            "title_ca": validated.title_ca,
            "title_es": validated.title_es,
            "body_ca": validated.body_ca,
            "body_es": validated.body_es,
            "source_up_ids": [str(u) for u in source_up_ids],
            "confidence_band": validated.confidence_band,
            "disclaimer_required": validated.disclaimer_required,
            "prompt_id": prompt_id,
            "prompt_version": prompt_version,
        }

    # ── dismiss ──────────────────────────────────────────────────────────────────

    async def dismiss(
        self, tenant_id: uuid.UUID, insight_id: uuid.UUID, *, user_id: uuid.UUID
    ) -> bool:
        """Write an InsightDismissal (idempotent) + audit AI_INSIGHT_DISMISSED."""
        exists = (
            await self._db.execute(
                text(
                    "SELECT 1 FROM insights WHERE id = :iid AND tenant_id = :tid "
                    "AND deleted_at IS NULL"
                ),
                {"iid": str(insight_id), "tid": str(tenant_id)},
            )
        ).scalar_one_or_none()
        if exists is None:
            from app.errors import AppError

            raise AppError(code="NOT_FOUND", status_code=404, message="Insight not found.")

        await self._db.execute(
            text(
                "INSERT INTO insight_dismissals (id, user_id, insight_id) "
                "VALUES (:id, :uid, :iid) ON CONFLICT (user_id, insight_id) DO NOTHING"
            ),
            {"id": str(uuid.uuid4()), "uid": str(user_id), "iid": str(insight_id)},
        )
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.AI_INSIGHT_DISMISSED,
                tenant_id=tenant_id,
                actor_user_id=user_id,
                entity_type="insight",
                entity_id=insight_id,
            )
        )
        await self._db.flush()
        return True

    # ── helpers: shared-table reads (raw SQL — no app.up import) ──────────────────

    async def _collect_recent_ups(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID
    ) -> tuple[list[uuid.UUID], str]:
        """Recent (<=7d) UP ids (capped 10) + a coarse summary. NO note text is read here —
        the summary is category counts only (the encrypted note never enters the payload)."""
        rows = (
            await self._db.execute(
                text(
                    "SELECT id, category FROM ups "
                    "WHERE tenant_id = :tid AND profile_id = :pid AND deleted_at IS NULL "
                    "AND occurred_at >= now() - interval '7 days' "
                    "ORDER BY occurred_at DESC LIMIT 10"
                ),
                {"tid": str(tenant_id), "pid": str(profile_id)},
            )
        ).all()
        up_ids = [uuid.UUID(str(r[0])) for r in rows]
        counts: dict[str, int] = {}
        for r in rows:
            counts[str(r[1])] = counts.get(str(r[1]), 0) + 1
        summary = ", ".join(f"{cat}: {n}" for cat, n in sorted(counts.items()))
        return up_ids, summary

    async def _fk_filter_up_ids(
        self, tenant_id: uuid.UUID, candidate_ids: list[uuid.UUID]
    ) -> list[uuid.UUID]:
        """Keep only the candidate ids that exist as live UPs for this tenant (FK validation)."""
        if not candidate_ids:
            return []
        rows = (
            await self._db.execute(
                text(
                    "SELECT id FROM ups WHERE tenant_id = :tid AND deleted_at IS NULL "
                    "AND id = ANY(cast(:ids as uuid[]))"
                ),
                {"tid": str(tenant_id), "ids": [str(u) for u in candidate_ids]},
            )
        ).all()
        return [uuid.UUID(str(r[0])) for r in rows]

    async def _active_spheres(self, tenant_id: uuid.UUID, profile_id: uuid.UUID) -> str:
        row = (
            await self._db.execute(
                text(
                    "SELECT active_esferes FROM profiles "
                    "WHERE tenant_id = :tid AND id = :pid "
                    "AND EXISTS (SELECT 1 FROM app_resolve_profile_temporal_access(:pid) "
                    "WHERE access_state = 'current')"
                ),
                {"tid": str(tenant_id), "pid": str(profile_id)},
            )
        ).scalar_one_or_none()
        if not row:
            return ""
        return ", ".join(str(s) for s in row)

    async def _tenant_locale(self, tenant_id: uuid.UUID) -> SupportedLocale:
        locale = (
            await self._db.execute(
                text("SELECT locale::text FROM tenants WHERE id = :tid"),
                {"tid": str(tenant_id)},
            )
        ).scalar_one_or_none()
        if locale not in {"ca", "es", "en"}:
            raise AiPipelineError("AI pseudonymisation locale is unsupported.")
        return cast(SupportedLocale, str(locale))

    async def _record_low_confidence_skip(
        self,
        *,
        confidence: float,
        artifact_manifest_version: str,
    ) -> None:
        """Q77: no provider call and no child/source/network identifiers in telemetry."""
        confidence_band = "below_0_85" if confidence < 0.85 else "at_or_above_0_85"
        await self._audit.append_ai_ner_low_confidence_skip(
            confidence_band=confidence_band,
            artifact_manifest_version=artifact_manifest_version,
        )
        try:
            import sentry_sdk

            # Clear both SDK scopes so request/user/breadcrumb context cannot turn this
            # intentionally aggregate signal into child- or family-linkable telemetry.
            with sentry_sdk.isolation_scope() as isolation:
                isolation.clear()
                with sentry_sdk.new_scope() as scope:
                    scope.clear()
                    scope.set_tag("locale", "ca")
                    scope.set_tag("confidence_band", confidence_band)
                    scope.set_tag("artifact_manifest_version", artifact_manifest_version)
                    sentry_sdk.capture_message(
                        "AI pseudonymisation skipped below the Catalan confidence floor",
                        level="warning",
                    )
        except Exception as exc:
            logger.warning(
                "ai_pseudonymisation_skip_telemetry_failed",
                error_type=type(exc).__name__,
            )
        await self._db.flush()

    async def _particularity_baseline(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID
    ) -> str | None:
        row = (
            await self._db.execute(
                text(
                    "SELECT particularity_baseline FROM profiles "
                    "WHERE tenant_id = :tid AND id = :pid "
                    "AND EXISTS (SELECT 1 FROM app_resolve_profile_temporal_access(:pid) "
                    "WHERE access_state = 'current')"
                ),
                {"tid": str(tenant_id), "pid": str(profile_id)},
            )
        ).scalar_one_or_none()
        if isinstance(row, dict):
            return row.get("baseline") or row.get("kind")
        if isinstance(row, str):
            return row
        return None

    async def _log_art9_inputs(self, tenant_id: uuid.UUID, up_ids: list[uuid.UUID]) -> None:
        """special_category_access_log on every Art-9 UP read into the AI payload."""
        from app.gdpr.special_category_log import SpecialCategoryAccessLogRepository

        repo = SpecialCategoryAccessLogRepository(self._db)
        for up_id in up_ids:
            await repo.append(
                tenant_id=tenant_id,
                resource_kind="up",
                resource_id=up_id,
                purpose="family_member_view",
                access_kind="read",
            )

    # ── SWR cache + DB read ───────────────────────────────────────────────────────

    async def _cache_get(self, key: str) -> dict | None:
        from redis.exceptions import RedisError

        from app.core.redis import get_redis

        redis = get_redis()
        try:
            raw = await redis.get(key)
            return json.loads(raw) if raw else None
        except (RedisError, OSError, ValueError):
            return None
        finally:
            await redis.aclose()

    async def _cache_set(self, key: str, value: dict) -> None:
        from redis.exceptions import RedisError

        from app.core.redis import get_redis

        redis = get_redis()
        try:
            await redis.set(key, json.dumps(value), ex=_SWR_TTL_SECONDS)
        except (RedisError, OSError):
            pass
        finally:
            await redis.aclose()

    async def _fresh_db_insight(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID, prompt_id: str, prompt_version: str
    ) -> dict | None:
        """Return the freshest live (<24h) persisted insight for the prompt, decrypted."""
        from app.encryption import decrypt_field_for_tenant

        row = (
            (
                await self._db.execute(
                    text(
                        "SELECT id, kind, body_encrypted, confidence_band, disclaimer_required, "
                        "generated_at FROM insights WHERE tenant_id = :tid AND profile_id = :pid "
                        "AND prompt_id = :pi AND prompt_version = :pv AND deleted_at IS NULL "
                        "AND state = 'published' AND generated_at >= now() - interval '24 hours' "
                        "ORDER BY generated_at DESC LIMIT 1"
                    ),
                    {
                        "tid": str(tenant_id),
                        "pid": str(profile_id),
                        "pi": prompt_id,
                        "pv": prompt_version,
                    },
                )
            )
            .mappings()
            .first()
        )
        if row is None:
            return None

        insight_id = uuid.UUID(str(row["id"]))
        plain = await decrypt_field_for_tenant(
            ciphertext=bytes(row["body_encrypted"]),
            tenant_id=tenant_id,
            column_key="Insight.body",
            row_id=insight_id,
            db=self._db,
        )
        body = json.loads(plain.decode("utf-8"))
        up_rows = (
            await self._db.execute(
                text("SELECT up_id FROM insight_up_links WHERE insight_id = :iid"),
                {"iid": str(insight_id)},
            )
        ).all()
        return {
            "id": str(insight_id),
            "kind": row["kind"],
            "title_ca": body.get("title_ca", ""),
            "title_es": body.get("title_es", ""),
            "body_ca": body.get("body_ca", ""),
            "body_es": body.get("body_es", ""),
            "source_up_ids": [str(r[0]) for r in up_rows],
            "confidence_band": row["confidence_band"],
            "disclaimer_required": row["disclaimer_required"],
            "prompt_id": prompt_id,
            "prompt_version": prompt_version,
        }

    # ── audit + observability ─────────────────────────────────────────────────────

    async def _audit_presented(
        self, tenant_id: uuid.UUID, profile_id: uuid.UUID, actor_user_id: uuid.UUID, insight_id
    ) -> None:
        meta = {"insight_id": str(insight_id)} if insight_id else None
        await self._audit.append(
            NewAuditEvent(
                event_kind=AuditEventKind.AI_INSIGHT_PRESENTED,
                tenant_id=tenant_id,
                actor_user_id=actor_user_id,
                entity_type="profile",
                entity_id=profile_id,
                meta=meta,
            )
        )
        await self._db.flush()

    def _log_computed(
        self,
        prompt_id: str,
        prompt_version: str,
        payload: dict,
        profile_id: uuid.UUID,
        est_in: int,
        validated: InsightResponse,
    ) -> None:
        """ai.insight.computed — HASHES + metadata ONLY (Step 10).

        EXPLICITLY NOT logged: prompt content, raw response, UP note text, profile name,
        tenant_id. Only one-way hashes + counts + bands.
        """
        payload_basis = json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
        logger.info(
            "ai.insight.computed",
            prompt_id=prompt_id,
            prompt_version=prompt_version,
            sha256_payload_prefix=hashlib.sha256(payload_basis).hexdigest()[:16],
            profile_id_hash=hashlib.sha256(str(profile_id).encode()).hexdigest()[:16],
            input_tokens=est_in,
            confidence_band=validated.confidence_band,
            kind=validated.kind.value,
            validation_pass=True,
        )
