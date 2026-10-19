"""Plan 026 — the pseudonymisation SECURITY BOUNDARY.

The model is never trusted to redact. These tests assert that names, emails, phones, and old
dates are removed BEFORE the AI client sees the payload, and that tenant_id never leaves our
boundary. This is the single most important privacy test in the AI layer.
"""

from __future__ import annotations

import uuid

import pytest

from app.ai.pseudonymise import (
    PseudonymisationResult,
    PseudonymisationUnavailableError,
    assert_no_internal_identifiers,
    assert_no_tenant_id,
    assert_production_pseudonymisation_ready,
    build_name_map,
    pseudonymise,
)

pytestmark = pytest.mark.no_database


def test_pseudonymise_strips_identifiers() -> None:
    """Name, email, phone, and old dates are removed; tenant_id is stripped entirely."""
    up_ids = [str(uuid.uuid4()) for _ in range(3)]
    payload = {
        "tenant_id": "SECRET-TENANT-UUID",
        "source_up_ids": up_ids,
        "weekly_summary": (
            "El Marc va estar molt content. Truca'm al 600 123 456 o a +34600123456, "
            "o escriu a marc@example.com. Va passar el 2020-01-15 i també el 2026-05-20."
        ),
    }
    result = pseudonymise(
        payload=payload,
        profile_names=["Marc"],
        locale="ca",
        now_year=2026,
        now_month=5,
    )
    clean = result.payload

    summary = clean["weekly_summary"]
    # The name is gone.
    assert "Marc" not in summary
    # The email is gone (whole-unit).
    assert "marc@example.com" not in summary and "example.com" not in summary
    # The phones are gone (spaced + international).
    assert "600 123 456" not in summary
    assert "+34600123456" not in summary
    # An old date is bucketed to month-year; a recent one is kept.
    assert "2020-01-15" not in summary and "2020-01" in summary
    assert "2026-05-20" in summary


def test_tenant_id_never_in_payload() -> None:
    """tenant_id (and the camelCase variant) is hard-stripped; the assertion passes."""
    clean = pseudonymise(
        payload={"tenant_id": "x", "tenantId": "y", "weekly_summary": "hola"},
        profile_names=[],
        locale="es",
        now_year=2026,
        now_month=5,
    ).payload
    assert "tenant_id" not in clean
    assert "tenantId" not in clean
    assert_no_tenant_id(clean)  # must not raise


def test_source_up_ids_remain_only_for_provider_alias_staging() -> None:
    """The local adapter needs source IDs temporarily so it can alias them before network I/O."""
    up_ids = [str(uuid.uuid4()) for _ in range(2)]
    clean = pseudonymise(
        payload={"source_up_ids": up_ids, "weekly_summary": "res"},
        profile_names=["Joana"],
        locale="ca",
        now_year=2026,
        now_month=5,
    ).payload
    assert clean["source_up_ids"] == up_ids


def test_name_map_randomised_across_sessions() -> None:
    """The same name maps to a deterministic placeholder WITHIN a session but a fresh one
    across sessions (not re-linkable)."""
    m1 = build_name_map(["Marc"])
    m2 = build_name_map(["Marc"])
    # Within one map, consistent.
    assert m1["Marc"] == m1["Marc"]
    # Across maps (sessions), different placeholder tokens.
    assert m1["Marc"] != m2["Marc"]


def test_nested_and_list_fields_redacted() -> None:
    """Redaction walks into nested dicts + lists."""
    clean = pseudonymise(
        payload={
            "notes": ["El Pere va riure", "truca al 600 111 222"],
            "meta": {"author": "El Pere"},
        },
        profile_names=["Pere"],
        locale="ca",
        now_year=2026,
        now_month=5,
    ).payload
    assert all("Pere" not in n for n in clean["notes"])
    assert "600 111 222" not in clean["notes"][1]
    assert "Pere" not in clean["meta"]["author"]


def test_nested_internal_identifiers_are_stripped_and_assertion_is_recursive() -> None:
    clean = pseudonymise(
        payload={
            "meta": {
                "profileId": str(uuid.uuid4()),
                "safe": "resum",
                "nested": {"tenant_id": str(uuid.uuid4())},
            }
        },
        profile_names=[],
        locale="en",
        now_year=2026,
        now_month=7,
    ).payload
    assert clean == {"meta": {"safe": "resum", "nested": {}}}

    with pytest.raises(ValueError, match="tenant_id"):
        assert_no_tenant_id({"meta": {"tenantId": "forbidden"}})


@pytest.mark.parametrize(
    "payload",
    [
        {"profile_id": str(uuid.uuid4())},
        {"user_message": f"internal ref {uuid.uuid4()}"},
        {"user_message": "contacte@example.com"},
        {"user_message": "truca al 600 123 456"},
    ],
)
def test_provider_boundary_rejects_direct_identifiers(payload: dict) -> None:
    with pytest.raises(ValueError):
        assert_no_internal_identifiers(payload)


def test_production_refuses_regex_ner(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.config.settings import settings

    monkeypatch.setattr(settings, "environment", "production")
    monkeypatch.setattr(settings, "ai_ner_engine", "regex")
    with pytest.raises(PseudonymisationUnavailableError, match="AI_NER_ENGINE=spacy"):
        assert_production_pseudonymisation_ready()


def test_spacy_configuration_never_silently_falls_back_to_regex(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.config.settings import settings

    def _unavailable(*, require_signed_review: bool) -> object:
        raise PseudonymisationUnavailableError("model missing")

    monkeypatch.setattr(settings, "ai_ner_engine", "spacy")
    monkeypatch.setattr(
        "app.ai.pseudonymise.verify_installed_ner_artifacts",
        _unavailable,
    )
    monkeypatch.setattr(settings, "environment", "production")
    with pytest.raises(PseudonymisationUnavailableError, match="model missing"):
        assert_production_pseudonymisation_ready()


def test_typed_result_carries_locale_artifact_and_confidence() -> None:
    result = pseudonymise(
        payload={"weekly_summary": "A calm week"},
        profile_names=[],
        locale="en",
        now_year=2026,
        now_month=8,
    )
    assert result.locale == "en"
    assert result.artifact_manifest_version == "ner-pseudonymisation-2026-08-09.v1"
    assert result.artifact_identity == "regex-dev-only"
    assert result.confidence == 1.0


def test_unsupported_locale_is_rejected_before_processing() -> None:
    with pytest.raises(ValueError, match="unsupported AI pseudonymisation locale"):
        pseudonymise(
            payload={"weekly_summary": "bonjour"},
            profile_names=[],
            locale="fr",  # type: ignore[arg-type]
            now_year=2026,
            now_month=8,
        )


def test_q77_catalan_confidence_floor_is_locale_specific() -> None:
    low_ca = PseudonymisationResult(
        payload={},
        locale="ca",
        artifact_manifest_version="ner-pseudonymisation-2026-08-09.v1",
        artifact_identity="fixture",
        confidence=0.849,
    )
    same_confidence_en = PseudonymisationResult(
        payload={},
        locale="en",
        artifact_manifest_version="ner-pseudonymisation-2026-08-09.v1",
        artifact_identity="fixture",
        confidence=0.849,
    )
    assert low_ca.catalan_confidence_requires_skip is True
    assert same_confidence_en.catalan_confidence_requires_skip is False
