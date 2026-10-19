"""PromptLoader + forbidden/hedge registries (Plan 026 Steps 3, 8, 9).

Loads the YAML prompt store under apps/api/prompts/v{N}/ + the shared forbidden_phrases.yaml
and required_hedges.yaml (all EUPL-1.2 open-source per Round-1 Public-good).

CRITICAL: a prompt with clinical_advisor_reviewed:false is REFUSED (raises) — an unreviewed
prompt must never reach a child's data. The production prompts' clinical review is Plan
080/082; the test/dev prompts are marked reviewed only so the dark pipeline is exercisable.

Prompt version resolution: immutable reviewed DB revisions are content-addressed and a durable
PostgreSQL activation pointer owns rollback. With no pointer, the reviewed live override (or the
committed YAML version) is active. prompt_version is part of the cache key + insight_hash, so an
edit or rollback partitions caches without relying on volatile Redis coordination.
"""

from __future__ import annotations

import functools
import hashlib
import uuid
from pathlib import Path
from typing import Any

import yaml
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

_PROMPTS_ROOT = Path(__file__).resolve().parents[2] / "prompts"


class PromptValidationError(Exception):
    """A prompt YAML is malformed or not clinical-advisor-reviewed → refuse to load."""


class PromptDef:
    """A loaded, validated prompt definition."""

    __slots__ = (
        "kind",
        "languages",
        "max_output_tokens",
        "prompt_id",
        "prompt_version",
        "required_hedge_set",
        "system_prompt",
        "temperature",
        "user_template",
    )

    def __init__(self, raw: dict[str, Any], *, source: str) -> None:
        self.prompt_id = _require(raw, "prompt_id", source)
        self.prompt_version = _require(raw, "prompt_version", source)
        self.kind = _require(raw, "kind", source)
        self.system_prompt = _require(raw, "system_prompt", source)
        self.user_template = raw.get("user_template", "")
        self.max_output_tokens = int(raw.get("max_output_tokens", 1024))
        self.temperature = float(raw.get("temperature", 0.3))
        self.required_hedge_set = raw.get("required_hedge_set")
        self.languages = list(raw.get("languages", ["ca", "es"]))

        # The hard gate: an unreviewed prompt is never loadable.
        if raw.get("clinical_advisor_reviewed") is not True:
            raise PromptValidationError(
                f"Prompt {source!r} has clinical_advisor_reviewed != true. "
                "An unreviewed prompt must not reach child data (Plan 080/082)."
            )

    def with_system_prompt(self, content: str, *, prompt_version: str) -> PromptDef:
        """Return an immutable effective view with reviewed database content."""
        return PromptDef(
            {
                "prompt_id": self.prompt_id,
                "prompt_version": prompt_version,
                "kind": self.kind,
                "system_prompt": content,
                "user_template": self.user_template,
                "max_output_tokens": self.max_output_tokens,
                "temperature": self.temperature,
                "required_hedge_set": self.required_hedge_set,
                "languages": self.languages,
                "clinical_advisor_reviewed": True,
            },
            source=f"database:{self.prompt_id}:{prompt_version}",
        )


def _require(raw: dict[str, Any], key: str, source: str) -> Any:
    if key not in raw or raw[key] in (None, ""):
        raise PromptValidationError(f"Prompt {source!r} missing required key {key!r}.")
    return raw[key]


@functools.lru_cache(maxsize=1)
def _load_all_prompts(version_dir: str = "v1") -> dict[str, PromptDef]:
    """Parse + validate every prompt YAML in prompts/{version_dir}/ (cached per process)."""
    root = _PROMPTS_ROOT / version_dir
    out: dict[str, PromptDef] = {}
    for path in sorted(root.glob("*.yaml")):
        # Skip the shared registries (they are not prompts).
        if path.name in {"forbidden_phrases.yaml", "required_hedges.yaml"}:
            continue
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            raise PromptValidationError(f"Prompt {path.name!r} is not a mapping.")
        prompt = PromptDef(raw, source=path.name)
        out[prompt.prompt_id] = prompt
    return out


def get_prompt(prompt_id: str, *, version_dir: str = "v1") -> PromptDef:
    """Return the validated PromptDef for a prompt_id (raises if missing/unreviewed)."""
    prompts = _load_all_prompts(version_dir)
    if prompt_id not in prompts:
        raise PromptValidationError(f"Unknown prompt_id {prompt_id!r}.")
    return prompts[prompt_id]


def list_prompt_ids(*, version_dir: str = "v1") -> list[str]:
    return sorted(_load_all_prompts(version_dir).keys())


def prompt_content_version(content: str) -> str:
    """Content-address a reviewed database prompt for cache/provenance stability."""
    return "db-" + hashlib.sha256(content.encode("utf-8")).hexdigest()[:20]


async def get_prompt_for_version(
    db: AsyncSession,
    prompt_id: str,
    prompt_version: str,
    *,
    version_dir: str = "v1",
) -> PromptDef:
    """Resolve exactly one reviewed prompt version; unknown versions fail closed."""
    from sqlalchemy import select

    from app.models.lookup import AiPrompt, AiPromptRevision

    committed = get_prompt(prompt_id, version_dir=version_dir)
    if prompt_version == committed.prompt_version:
        return committed

    revision = (
        await db.execute(
            select(AiPromptRevision).where(
                AiPromptRevision.prompt_id == prompt_id,
                AiPromptRevision.version == prompt_version,
            )
        )
    ).scalar_one_or_none()
    if revision is not None:
        if revision.requires_signoff and not revision.clinical_reviewed:
            raise PromptValidationError(
                f"Prompt {prompt_id!r} version {prompt_version!r} lacks clinical sign-off."
            )
        return committed.with_system_prompt(
            revision.content,
            prompt_version=revision.version,
        )

    live = (
        await db.execute(select(AiPrompt).where(AiPrompt.prompt_id == prompt_id))
    ).scalar_one_or_none()
    if live is not None and prompt_content_version(live.content) == prompt_version:
        # Legacy rows predate the revision ledger. reviewed_at proves the live content was
        # signed off even if a newer pending edit set the historical boolean false.
        reviewed = (
            not live.requires_signoff or live.clinical_reviewed or live.reviewed_at is not None
        )
        if not reviewed:
            raise PromptValidationError(
                f"Prompt {prompt_id!r} database override lacks clinical sign-off."
            )
        return committed.with_system_prompt(live.content, prompt_version=prompt_version)

    raise PromptValidationError(
        f"Unknown or unavailable prompt version {prompt_version!r} for {prompt_id!r}."
    )


async def active_prompt_version(
    prompt_id: str,
    *,
    db: AsyncSession | None = None,
    version_dir: str = "v1",
) -> str:
    """Return the durable active override, reviewed live DB version, or file default."""
    committed = get_prompt(prompt_id, version_dir=version_dir)
    if db is None:
        return committed.prompt_version

    from sqlalchemy import select

    from app.models.lookup import AiPrompt, AiPromptActiveVersion

    active = (
        await db.execute(
            select(AiPromptActiveVersion.version).where(
                AiPromptActiveVersion.prompt_id == prompt_id
            )
        )
    ).scalar_one_or_none()
    if active is not None:
        # The write path validates this pointer before persisting it. Re-resolve on read
        # so a corrupted or stale pointer still fails closed before child data is sent.
        await get_prompt_for_version(db, prompt_id, active, version_dir=version_dir)
        return active

    live = (
        await db.execute(select(AiPrompt).where(AiPrompt.prompt_id == prompt_id))
    ).scalar_one_or_none()
    if live is None or live.content == committed.system_prompt:
        return committed.prompt_version
    reviewed = not live.requires_signoff or live.clinical_reviewed or live.reviewed_at is not None
    if not reviewed:
        raise PromptValidationError(f"Prompt {prompt_id!r} database override lacks sign-off.")
    return prompt_content_version(live.content)


async def set_active_prompt_version(
    db: AsyncSession,
    prompt_id: str,
    version: str,
    *,
    updated_by: uuid.UUID | None = None,
    reason: str = "manual rollback",
) -> None:
    """Validate and persist the active reviewed prompt version atomically."""
    from sqlalchemy.dialects.postgresql import insert

    from app.models.lookup import AiPromptActiveVersion

    await get_prompt_for_version(db, prompt_id, version)
    statement = insert(AiPromptActiveVersion).values(
        prompt_id=prompt_id,
        version=version,
        reason=reason,
        updated_by=updated_by,
    )
    await db.execute(
        statement.on_conflict_do_update(
            index_elements=[AiPromptActiveVersion.prompt_id],
            set_={
                "version": statement.excluded.version,
                "reason": statement.excluded.reason,
                "updated_by": statement.excluded.updated_by,
                "updated_at": text("now()"),
            },
        )
    )


# ── Forbidden-phrase + required-hedge registries (the voice-lock eval source of truth) ──


@functools.lru_cache(maxsize=1)
def load_forbidden_phrases(*, version_dir: str = "v1") -> list[str]:
    raw = yaml.safe_load(
        (_PROMPTS_ROOT / version_dir / "forbidden_phrases.yaml").read_text(encoding="utf-8")
    )
    return [str(p) for p in raw.get("forbidden", [])]


@functools.lru_cache(maxsize=1)
def load_required_hedges(*, version_dir: str = "v1") -> dict[str, list[str]]:
    raw = yaml.safe_load(
        (_PROMPTS_ROOT / version_dir / "required_hedges.yaml").read_text(encoding="utf-8")
    )
    hedges = raw.get("required_hedges", {})
    return {lang: [str(h) for h in terms] for lang, terms in hedges.items()}
