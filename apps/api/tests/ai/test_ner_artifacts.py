from __future__ import annotations

from dataclasses import replace

import pytest

from app.ai import ner_artifacts
from app.ai.ner_artifacts import (
    NerArtifactUnavailableError,
    NerReviewStatus,
    build_verified_ner_model,
    load_ner_artifact_manifest,
)

pytestmark = pytest.mark.no_database


def test_manifest_pins_exact_trilingual_artifact_set() -> None:
    manifest = load_ner_artifact_manifest()
    assert manifest.spacy_version == "3.8.14"
    assert set(manifest.models) == {"ca", "es", "en"}
    assert manifest.review_status is NerReviewStatus.PENDING_EXTERNAL
    assert manifest.clinical_advisor_identity is None
    assert manifest.signed_attestation_sha256 is None
    assert all(model.version == "3.8.0" for model in manifest.models.values())
    assert all(len(model.wheel_sha256) == 64 for model in manifest.models.values())
    assert {locale: model.upstream_ents_f for locale, model in manifest.models.items()} == {
        "ca": 0.8479427549,
        "es": 0.8970169298,
        "en": 0.8553967422,
    }
    assert manifest.catalan_skip_below == 0.85


def test_pending_external_review_is_intrinsically_fail_closed() -> None:
    manifest = load_ner_artifact_manifest()
    with pytest.raises(NerArtifactUnavailableError, match="clinical review is pending"):
        ner_artifacts._verify_signed_review(manifest)


def test_manifest_fixture_corpus_digest_matches_repository_file() -> None:
    ner_artifacts._verify_fixture_corpus(load_ner_artifact_manifest())


def test_placeholder_reviewer_cannot_satisfy_signed_state() -> None:
    manifest = replace(
        load_ner_artifact_manifest(),
        review_status=NerReviewStatus.SIGNED,
        clinical_advisor_identity="@clinical-advisor",
        reviewed_at="2026-08-09T00:00:00Z",
        signed_attestation_path="docs/legal/fake.json",
        signed_attestation_sha256="0" * 64,
    )
    with pytest.raises(NerArtifactUnavailableError, match="placeholder"):
        ner_artifacts._verify_signed_review(manifest)


def test_signed_state_requires_in_image_digest_bound_attestation() -> None:
    manifest = replace(
        load_ner_artifact_manifest(),
        review_status=NerReviewStatus.SIGNED,
        clinical_advisor_identity="Dr Example Reviewer",
        reviewed_at="2026-08-09T00:00:00Z",
        signed_attestation_path="../outside-artifact-boundary.pdf",
        signed_attestation_sha256="0" * 64,
    )
    with pytest.raises(NerArtifactUnavailableError, match="attestation is unavailable"):
        ner_artifacts._verify_signed_review(manifest)


def test_signed_state_requires_timezone_bound_review_timestamp() -> None:
    manifest = replace(
        load_ner_artifact_manifest(),
        review_status=NerReviewStatus.SIGNED,
        clinical_advisor_identity="Dr Example Reviewer",
        reviewed_at="2026-08-09T00:00:00",
        signed_attestation_path="review.pdf",
        signed_attestation_sha256="0" * 64,
    )
    with pytest.raises(NerArtifactUnavailableError, match="include a timezone"):
        ner_artifacts._verify_signed_review(manifest)


def test_unreviewed_model_loader_is_unavailable_outside_image_build(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ESFERAUP_NER_BUILD_VERIFICATION", raising=False)
    with (
        pytest.raises(NerArtifactUnavailableError, match="build-only"),
        build_verified_ner_model("ca"),
    ):
        pass


def test_manifest_rejects_unsupported_locale() -> None:
    with pytest.raises(ValueError, match="unsupported AI pseudonymisation locale"):
        load_ner_artifact_manifest().model_for("fr")
