"""The Gemini model for the text uses: AI Patrons, Arxiu OCR and Activa authoring text.

One setting drives the three (ADR-017, amended 2026-10-06): the default an internal admin
saves in ``ai_global_config.default_model``. It is honoured only while it is GA and in
``allowed_models()``; with nothing saved, or a saved id that is no longer allowed, the
environment's ``GEMINI_MODEL_NAME`` applies. The location is never chosen here: every text
use runs in ``GEMINI_LOCATION`` (EU), so each allowed model must be served there.

Luma comprehension, Luma read-aloud audio and Activa illustrations have their own model and
location settings and do not read this.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import structlog
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.config.settings import is_ga_model_id, settings

if TYPE_CHECKING:
    from sqlalchemy.ext.asyncio import AsyncSession

logger = structlog.get_logger(__name__)

_STORED_DEFAULT = text("SELECT default_model FROM ai_global_config WHERE id = 1")


def allowed_models() -> list[str]:
    """Models an admin may select: ``GEMINI_MODEL_NAME`` plus ``GEMINI_SELECTABLE_MODELS``.

    Preview and experimental ids are left out in every environment (their terms forbid
    personal data of under-18s); production refuses to boot with one configured.
    """
    configured = dict.fromkeys([settings.gemini_model_name, *settings.gemini_selectable_models])
    return [model for model in configured if is_ga_model_id(model)]


def effective_text_model(stored: str | None) -> str:
    """The saved default while it is still allowed, else the environment model."""
    if stored and stored in allowed_models():
        return stored
    return settings.gemini_model_name


async def _stored_default(db: AsyncSession | None) -> str | None:
    if db is not None:
        return (await db.execute(_STORED_DEFAULT)).scalar()

    from app.db.session import AsyncSessionLocal

    async with AsyncSessionLocal() as session:
        return (await session.execute(_STORED_DEFAULT)).scalar()


async def resolve_text_model(db: AsyncSession | None = None) -> str:
    """The model a Patrons or OCR call must use now.

    Adapters have no request session and read the saved default on a short one of their
    own. If it cannot be read, the environment model is used: it is the validated baseline.
    """
    try:
        stored = await _stored_default(db)
    except (SQLAlchemyError, OSError):
        logger.warning("ai_text_model_read_failed_using_environment")
        stored = None
    return effective_text_model(stored)
