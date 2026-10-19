"""The stored AI default model left Gemini 2.5 (0239, ADR-017)."""

import pytest
from sqlalchemy import text

pytestmark = pytest.mark.integration


async def test_the_stored_and_column_default_model_is_gemini_3(db_session) -> None:
    stored = (
        await db_session.execute(text("SELECT default_model FROM ai_global_config WHERE id = 1"))
    ).scalar_one()
    column_default = (
        await db_session.execute(
            text(
                "SELECT column_default FROM information_schema.columns "
                "WHERE table_name = 'ai_global_config' AND column_name = 'default_model'"
            )
        )
    ).scalar_one()
    assert stored == "gemini-3.1-flash-lite"
    assert "gemini-3.1-flash-lite" in column_default
    assert "2.5" not in column_default
