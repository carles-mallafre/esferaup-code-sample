"""AI Patrons domain (Plan 026) — DARK, flag-gated until DPIA + validation study (Plan 082).

This package owns the shared AI infrastructure: the pluggable AIClient (stub at MVP), the
fail-closed dual gate + EU AI Act kill switch, the pseudonymisation security boundary, the
k-anonymity check, the cost circuit breaker, the YAML prompt store + loader, the structured-
output Insight schema, the voice-lock detectors, and the InsightService pipeline.

DOMAIN ISOLATION (import-linter): app.ai MUST NOT import app.up / app.observation /
app.document. The UP-delete → insight-invalidation cascade is bridged via the transactional
OUTBOX (app.up emits up.deleted; the outbox drainer's AI topic handler soft-deletes citing
insights), NEVER by a cross-domain import.
"""
