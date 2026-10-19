# EsferaUp: code sample

A curated excerpt from **EsferaUp**, a trilingual (Catalan, Spanish, English) family platform
I designed and built end to end. Families capture *UPs* ("units of progress"): short moments
in a child's life, with mood, tags, photos and voice notes. Schools, clubs and specialists add
their own observations around them.

The full product is a monorepo with a Flutter app, three Next.js dashboards, an Astro site and
a FastAPI backend. This repository holds one vertical slice of it, chosen to show two things:

1. **A feature built end to end**: the UP feature, from the Flutter screens to the FastAPI
   routes, services, repositories and tests.
2. **How I integrate AI into a product that handles children's data**: the AI layer, where
   every call goes through consent, a fail-closed kill switch, pseudonymisation, a k-anonymity
   check, a cost breaker and an output "voice lock" before anything reaches a family.

> This is an excerpt for review. It does not build on its own, because the rest of the
> monorepo (shared core modules, migrations, infrastructure) is not included.

## Where to look first

| If you have… | Read |
| --- | --- |
| 5 minutes | [`apps/api/app/ai/insight_service.py`](apps/api/app/ai/insight_service.py): the AI pipeline, one gate per step |
| 10 more | [`pseudonymise.py`](apps/api/app/ai/pseudonymise.py), [`gate.py`](apps/api/app/ai/gate.py), [`cost_breaker.py`](apps/api/app/ai/cost_breaker.py) |
| Mobile | [`apps/mobile/lib/features/up/`](apps/mobile/lib/features/up/): data, domain and presentation layers of the UP feature |
| Backend feature | [`apps/api/app/services/up_service.py`](apps/api/app/services/up_service.py) and [`app/up/permissions.py`](apps/api/app/up/permissions.py) |
| Tests | [`apps/api/tests/ai/`](apps/api/tests/ai/), [`tests/ai_evals/`](apps/api/tests/ai_evals/) and [`apps/mobile/test/features/up/`](apps/mobile/test/features/up/) |

## The AI layer (`apps/api/app/ai`)

The AI feature ("Patrons") gives families gentle weekly insights from their own UPs. Because
it runs over data about minors, the design starts from what must never happen and makes each
of those a gate in code, not an instruction in a prompt.

```
request
  → gate.py            fail-closed feature flag + global kill switch (checked first)
  → consent_service    explicit, per-profile, revocable consent
  → pseudonymise.py    strip direct identifiers BEFORE the call (NER + rules);
                       the model is never trusted to redact
  → k_anonymity.py     the profile must sit in a cohort of at least k; otherwise a generic answer
  → cost_breaker.py    estimate and charge the cost before calling; stop runaways early
  → client / adapters  Gemini (API or Vertex) behind one interface, with a stub for tests
  → schema.py          structured output, validated
  → voice_lock.py      reject forbidden phrases (no diagnoses) and require hedging in every language
  → cascade.py         if a source UP is deleted, insights that cite it are invalidated
```

Other pieces worth a look:

- **`prompt_registry.py` / `prompts/v1/*.yaml`**: prompts are versioned files. Prompts that
  run over child data need clinical sign-off before an edit goes live.
- **`tests/ai_evals/`**: an adversarial NER set (names, emails, places hidden in Catalan and
  Spanish text) that the pseudonymiser must catch, plus a voice-lock eval.
- **Domain isolation**: `app.ai` never imports `app.up`. Deleting a UP reaches the AI domain
  through a transactional outbox event, not a cross-domain import.

## The UP feature

**Flutter (`apps/mobile`)**: Riverpod (with code generation), Freezed, GoRouter and Dio, in a
data/domain/presentation layout. The capture flow handles photos, audio recording with
permission sheets, mood and tags, and presigned uploads where sensitive bytes live in a
session-fenced cache that is wiped on logout. It also covers soft delete with "recently
deleted" restore, and sharing. Strings are localised in three languages, and the
tests cover interactions, accessibility (screen-reader labels, large text) and localisation.

**FastAPI (`apps/api`)**: async SQLAlchemy and PostgreSQL. Routes stay thin. `up_service`
holds the rules (attachments, history-only reads for past members, restore), and
`up/permissions.py` resolves who may see a UP from live family membership. A missing row and a
missing permission return the same opaque error on purpose, so IDs can't be probed.

## Numbers

- About 35k lines across 236 files in this excerpt
- 201 backend tests in 29 files, and 77 Flutter tests in 16 files, all included here
- The whole product: about 1,600 commits over six months, built with Claude Code and Codex as
  everyday pair-programmers

---

Carles Mallafré · Full-stack engineer, mobile apps and AI integration ·
[mobile-software-solutions.com](https://www.mobile-software-solutions.com/)

© 2026 Carles Mallafré. Shared for evaluation. All rights reserved; not licensed for reuse.
