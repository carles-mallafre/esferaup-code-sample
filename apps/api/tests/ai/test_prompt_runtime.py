from __future__ import annotations

import pytest

from app.ai.prompts import (
    PromptValidationError,
    active_prompt_version,
    get_prompt_for_version,
    prompt_content_version,
    set_active_prompt_version,
)
from app.errors import AppError
from app.services.ai_prompt_service import AiPromptService

pytestmark = pytest.mark.asyncio


async def test_signed_prompt_override_changes_runtime_and_preserves_history(
    family_ctx: dict, redis_flush: None
) -> None:
    db = family_ctx["db"]
    reviewer_id = family_ctx["admin_id"]
    service = AiPromptService.from_session(db)
    first_content = "Contingut clínicament revisat per orientar hipòtesis amb prudència."

    assert (
        await service.save("insight_family_weekly", first_content, reviewer_id) == "pending_signoff"
    )
    assert await active_prompt_version("insight_family_weekly", db=db) == "v1"

    assert await service.sign_off("insight_family_weekly", reviewer_id) == "signed_off"
    first_version = prompt_content_version(first_content)
    assert await active_prompt_version("insight_family_weekly", db=db) == first_version
    first = await get_prompt_for_version(db, "insight_family_weekly", first_version)
    assert first.system_prompt == first_content

    second_content = "Segona versió revisada, sempre orientativa i sense afirmacions clíniques."
    await service.save("insight_family_weekly", second_content, reviewer_id)
    # A pending edit never replaces or disables the reviewed live content.
    assert await active_prompt_version("insight_family_weekly", db=db) == first_version
    assert (
        await get_prompt_for_version(db, "insight_family_weekly", first_version)
    ).system_prompt == first_content

    await service.sign_off("insight_family_weekly", reviewer_id)
    second_version = prompt_content_version(second_content)
    assert await active_prompt_version("insight_family_weekly", db=db) == second_version

    await set_active_prompt_version(
        db,
        "insight_family_weekly",
        first_version,
        updated_by=reviewer_id,
        reason="regression rollback",
    )
    assert await active_prompt_version("insight_family_weekly", db=db) == first_version
    assert (
        await get_prompt_for_version(db, "insight_family_weekly", first_version)
    ).system_prompt == first_content


async def test_prompt_template_rejects_missing_or_unknown_placeholders(family_ctx: dict) -> None:
    service = AiPromptService.from_session(family_ctx["db"])
    with pytest.raises(AppError) as exc:
        await service.save(
            "activa.skeleton",
            "Genera {n} exercicis sense el breu requerit i amb {unknown}.",
            family_ctx["admin_id"],
        )
    assert exc.value.code == "INVALID_PROMPT_TEMPLATE"


async def test_prompt_rollback_rejects_unknown_or_unreviewed_version(family_ctx: dict) -> None:
    with pytest.raises(PromptValidationError, match="Unknown or unavailable"):
        await set_active_prompt_version(
            family_ctx["db"],
            "insight_family_weekly",
            "db-does-not-exist",
        )
