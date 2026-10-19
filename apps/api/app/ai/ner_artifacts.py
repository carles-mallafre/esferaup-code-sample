"""Versioned NER artifact identity and fail-closed production verification."""

from __future__ import annotations

import base64
import contextlib
import ctypes
import gc
import hashlib
import importlib
import importlib.metadata
import json
import threading
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal, cast

SupportedLocale = Literal["ca", "es", "en"]
SUPPORTED_LOCALES = frozenset({"ca", "es", "en"})
_MANIFEST_PATH = Path(__file__).with_name("artifacts") / "ner-manifest.v1.json"
_API_ROOT = _MANIFEST_PATH.parents[3]
_ATTESTATION_ROOT = _MANIFEST_PATH.parent / "attestations"
_FIXTURE_CORPUS_PATH = _API_ROOT / "tests" / "ai_evals" / "ner_adversarial.v1.json"


class NerArtifactUnavailableError(RuntimeError):
    """The exact reviewed NER artifact set is not available."""


class NerReviewStatus(StrEnum):
    PENDING_EXTERNAL = "pending_external"
    SIGNED = "signed"


@dataclass(frozen=True, slots=True)
class NerModelArtifact:
    locale: SupportedLocale
    distribution: str
    import_name: str
    version: str
    language: str
    wheel_url: str
    wheel_size_bytes: int
    wheel_sha256: str
    license: str
    upstream_release_commit: str
    upstream_ents_f: float
    expected_default_pipeline: tuple[str, ...]
    required_ner_labels: frozenset[str]

    @property
    def identity(self) -> str:
        return f"{self.distribution}=={self.version}@sha256:{self.wheel_sha256}"


@dataclass(frozen=True, slots=True)
class NerArtifactManifest:
    schema_version: int
    manifest_version: str
    spacy_distribution: str
    spacy_version: str
    max_text_chars: int
    beam_width: int
    beam_density: float
    redaction_candidate_floor: float
    catalan_skip_below: float
    container_max_rss_mib_per_model: int
    container_max_seconds_per_model: int
    review_status: NerReviewStatus
    clinical_advisor_identity: str | None
    reviewed_at: str | None
    fixture_corpus_sha256: str | None
    signed_attestation_path: str | None
    signed_attestation_sha256: str | None
    models: dict[SupportedLocale, NerModelArtifact]

    def model_for(self, locale: str) -> NerModelArtifact:
        if locale not in SUPPORTED_LOCALES:
            raise ValueError(f"unsupported AI pseudonymisation locale: {locale!r}")
        return self.models[cast(SupportedLocale, locale)]


def _require_sha256(value: object, *, field: str) -> str:
    digest = str(value)
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise NerArtifactUnavailableError(f"invalid sha256 in NER manifest: {field}")
    return digest


@lru_cache(maxsize=1)
def load_ner_artifact_manifest() -> NerArtifactManifest:
    try:
        raw = json.loads(_MANIFEST_PATH.read_text(encoding="utf-8"))
        if raw["schema_version"] != 1:
            raise NerArtifactUnavailableError("unsupported NER manifest schema")
        runtime = raw["runtime"]
        review = raw["review"]
        spacy = raw["spacy"]
        models: dict[SupportedLocale, NerModelArtifact] = {}
        if set(raw["models"]) != SUPPORTED_LOCALES:
            raise NerArtifactUnavailableError("NER manifest must define exactly ca/es/en")
        for locale_value, item in raw["models"].items():
            locale = cast(SupportedLocale, locale_value)
            if item["language"] != locale:
                raise NerArtifactUnavailableError(f"NER artifact language mismatch: {locale}")
            models[locale] = NerModelArtifact(
                locale=locale,
                distribution=str(item["distribution"]),
                import_name=str(item["import_name"]),
                version=str(item["version"]),
                language=str(item["language"]),
                wheel_url=str(item["wheel_url"]),
                wheel_size_bytes=int(item["wheel_size_bytes"]),
                wheel_sha256=_require_sha256(
                    item["wheel_sha256"], field=f"models.{locale}.wheel_sha256"
                ),
                license=str(item["license"]),
                upstream_release_commit=str(item["upstream_release_commit"]),
                upstream_ents_f=float(item["upstream_ents_f"]),
                expected_default_pipeline=tuple(item["expected_default_pipeline"]),
                required_ner_labels=frozenset(item["required_ner_labels"]),
            )
        return NerArtifactManifest(
            schema_version=1,
            manifest_version=str(raw["manifest_version"]),
            spacy_distribution=str(spacy["distribution"]),
            spacy_version=str(spacy["version"]),
            max_text_chars=int(runtime["max_text_chars"]),
            beam_width=int(runtime["beam_width"]),
            beam_density=float(runtime["beam_density"]),
            redaction_candidate_floor=float(runtime["redaction_candidate_floor"]),
            catalan_skip_below=float(runtime["catalan_skip_below"]),
            container_max_rss_mib_per_model=int(runtime["container_max_rss_mib_per_model"]),
            container_max_seconds_per_model=int(runtime["container_max_seconds_per_model"]),
            review_status=NerReviewStatus(review["status"]),
            clinical_advisor_identity=review["clinical_advisor_identity"],
            reviewed_at=review["reviewed_at"],
            fixture_corpus_sha256=review["fixture_corpus_sha256"],
            signed_attestation_path=review["signed_attestation_path"],
            signed_attestation_sha256=review["signed_attestation_sha256"],
            models=models,
        )
    except NerArtifactUnavailableError:
        raise
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise NerArtifactUnavailableError("invalid NER artifact manifest") from exc


def _verify_signed_review(manifest: NerArtifactManifest) -> None:
    if manifest.review_status is not NerReviewStatus.SIGNED:
        raise NerArtifactUnavailableError(
            "NER artifact clinical review is pending; production AI remains disabled"
        )
    required = (
        manifest.clinical_advisor_identity,
        manifest.reviewed_at,
        manifest.fixture_corpus_sha256,
        manifest.signed_attestation_path,
        manifest.signed_attestation_sha256,
    )
    if not all(required):
        raise NerArtifactUnavailableError("signed NER review metadata is incomplete")
    if str(manifest.clinical_advisor_identity).startswith(("TODO", "@clinical-advisor")):
        raise NerArtifactUnavailableError("placeholder NER clinical reviewer is forbidden")
    try:
        reviewed_at = datetime.fromisoformat(str(manifest.reviewed_at).replace("Z", "+00:00"))
    except ValueError as exc:
        raise NerArtifactUnavailableError("invalid NER review timestamp") from exc
    if reviewed_at.tzinfo is None:
        raise NerArtifactUnavailableError("NER review timestamp must include a timezone")
    _require_sha256(manifest.fixture_corpus_sha256, field="review.fixture_corpus_sha256")
    expected = _require_sha256(
        manifest.signed_attestation_sha256, field="review.signed_attestation_sha256"
    )
    attestation = (_ATTESTATION_ROOT / str(manifest.signed_attestation_path)).resolve()
    attestation_root = _ATTESTATION_ROOT.resolve()
    if attestation_root not in attestation.parents or not attestation.is_file():
        raise NerArtifactUnavailableError("signed NER review attestation is unavailable")
    if hashlib.sha256(attestation.read_bytes()).hexdigest() != expected:
        raise NerArtifactUnavailableError("signed NER review attestation digest mismatch")


def _verify_fixture_corpus(manifest: NerArtifactManifest) -> None:
    expected = _require_sha256(manifest.fixture_corpus_sha256, field="review.fixture_corpus_sha256")
    if not _FIXTURE_CORPUS_PATH.is_file():
        raise NerArtifactUnavailableError("NER adversarial fixture corpus is unavailable")
    if hashlib.sha256(_FIXTURE_CORPUS_PATH.read_bytes()).hexdigest() != expected:
        raise NerArtifactUnavailableError("NER adversarial fixture corpus digest mismatch")


def _verify_distribution_record(distribution: str) -> None:
    """Verify every installed file carrying a wheel RECORD sha256 entry."""
    dist = importlib.metadata.distribution(distribution)
    files = dist.files
    if not files:
        raise NerArtifactUnavailableError(f"installed distribution has no RECORD: {distribution}")
    checked = 0
    for package_path in files:
        file_hash = package_path.hash
        if file_hash is None or file_hash.mode != "sha256":
            continue
        path = Path(str(dist.locate_file(package_path)))
        if not path.is_file():
            raise NerArtifactUnavailableError(
                f"installed NER artifact file is missing: {path.name}"
            )
        actual = hashlib.sha256(path.read_bytes()).digest()
        expected = base64.urlsafe_b64decode(file_hash.value + "===")
        if actual != expected:
            raise NerArtifactUnavailableError(
                f"installed NER artifact file digest mismatch: {package_path}"
            )
        checked += 1
    if checked == 0:
        raise NerArtifactUnavailableError(f"no sha256 RECORD entries found: {distribution}")


def _installed_model_meta(module: Any, *, locale: SupportedLocale) -> dict[str, Any]:
    module_file = getattr(module, "__file__", None)
    if not module_file:
        raise NerArtifactUnavailableError(f"NER model package path is unavailable: {locale}")
    try:
        value = json.loads(
            (Path(str(module_file)).parent / "meta.json").read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as exc:
        raise NerArtifactUnavailableError(f"NER model metadata is unavailable: {locale}") from exc
    if not isinstance(value, dict):
        raise NerArtifactUnavailableError(f"NER model metadata is invalid: {locale}")
    return value


@lru_cache(maxsize=2)
def verify_installed_ner_artifacts(
    *, require_signed_review: bool, verify_record_files: bool = True
) -> NerArtifactManifest:
    manifest = load_ner_artifact_manifest()
    _verify_fixture_corpus(manifest)
    if require_signed_review:
        _verify_signed_review(manifest)
    try:
        installed_spacy = importlib.metadata.version(manifest.spacy_distribution)
    except importlib.metadata.PackageNotFoundError as exc:
        raise NerArtifactUnavailableError("spaCy is not installed") from exc
    if installed_spacy != manifest.spacy_version:
        raise NerArtifactUnavailableError(
            f"spaCy version mismatch: expected {manifest.spacy_version}, got {installed_spacy}"
        )
    if verify_record_files:
        _verify_distribution_record(manifest.spacy_distribution)
    for locale, artifact in manifest.models.items():
        try:
            installed_version = importlib.metadata.version(artifact.distribution)
        except importlib.metadata.PackageNotFoundError as exc:
            raise NerArtifactUnavailableError(f"NER model is not installed: {locale}") from exc
        if installed_version != artifact.version:
            raise NerArtifactUnavailableError(
                f"NER model version mismatch for {locale}: expected {artifact.version}, "
                f"got {installed_version}"
            )
        module = importlib.import_module(artifact.import_name)
        meta = _installed_model_meta(module, locale=locale)
        if meta.get("lang") != artifact.language or meta.get("version") != artifact.version:
            raise NerArtifactUnavailableError(f"NER model metadata mismatch for {locale}")
        if tuple(meta.get("pipeline", ())) != artifact.expected_default_pipeline:
            raise NerArtifactUnavailableError(f"NER pipeline mismatch for {locale}")
        labels = frozenset(meta.get("labels", {}).get("ner", ()))
        if not artifact.required_ner_labels.issubset(labels):
            raise NerArtifactUnavailableError(f"NER label set mismatch for {locale}")
        ents_f = float(meta.get("performance", {}).get("ents_f", -1.0))
        if abs(ents_f - artifact.upstream_ents_f) > 0.000001:
            raise NerArtifactUnavailableError(f"NER evaluation metadata mismatch for {locale}")
        if verify_record_files:
            _verify_distribution_record(artifact.distribution)
    return manifest


_resident_model_lock = threading.RLock()
_resident_locale: SupportedLocale | None = None
_resident_model: Any | None = None


def _release_resident_model() -> None:
    global _resident_locale, _resident_model
    _resident_locale = None
    _resident_model = None
    gc.collect()
    with contextlib.suppress(AttributeError, OSError):
        libc = ctypes.CDLL(None)
        libc.malloc_trim(0)


def _swap_resident_model(locale: SupportedLocale, *, require_signed_review: bool) -> Any:
    global _resident_locale, _resident_model
    manifest = verify_installed_ner_artifacts(require_signed_review=require_signed_review)
    if _resident_locale == locale and _resident_model is not None:
        return _resident_model
    _release_resident_model()
    artifact = manifest.model_for(locale)
    module = importlib.import_module(artifact.import_name)
    disabled = [
        component
        for component in artifact.expected_default_pipeline
        if component not in {"tok2vec", "ner"}
    ]
    model = module.load(disable=disabled)
    if "ner" not in model.pipe_names:
        raise NerArtifactUnavailableError(f"NER component unavailable for {locale}")
    _resident_locale = locale
    _resident_model = model
    return _resident_model


@contextlib.contextmanager
def verified_ner_model(locale: SupportedLocale) -> Any:
    """Hold the process-wide model lock so at most one locale model is resident/in use."""
    with _resident_model_lock:
        yield _swap_resident_model(locale, require_signed_review=True)


@contextlib.contextmanager
def build_verified_ner_model(
    locale: SupportedLocale, *, permit_pending_review: bool = False
) -> Any:
    """Exercise the same resident-model swap during an explicitly marked image build."""
    if not permit_pending_review:
        raise NerArtifactUnavailableError("unreviewed NER model loading is build-only")
    with _resident_model_lock:
        yield _swap_resident_model(locale, require_signed_review=False)


def manifest_path() -> Path:
    return _MANIFEST_PATH
