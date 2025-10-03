# Post-Release Follow-Up Items (v0.4.0 → v0.5.0 Planning)

Use this list to open GitHub issues immediately after v0.4.0 tag to maintain momentum and traceability.

## 1. Remove Artifact Fallback & Expand Guard

- Title: Remove Base.vi/Head.vi fallback & expand guard scope
- Description: Drop legacy name resolution in compare scripts/tests; extend guard tests to scripts and key docs. Provide migration grace messaging in release notes.
- Labels: migration, breaking-change-warning, v0.5.0

## 2. Outcome Classification Enhancements

- Title: Enrich outcome block with detailed discovery vs execution vs infrastructure breakdown
- Description: Add sub-fields clarifying classification sources; evaluate severity rank refinement; maintain additive schema rules.
- Labels: telemetry, schema, enhancement

## 3. Coverage Integration (Optional)

- Title: Add optional code coverage support for Integration-tagged tests
- Description: Investigate lightweight PS-based coverage or external tooling; ensure opt-in to avoid overhead.
- Labels: testing, enhancement

## 4. Documentation Pruning & Consolidation

- Title: Prune outdated examples and consolidate migration notes post-fallback removal
- Description: Remove legacy references; collapse duplicate guidance across README and runbook docs.
- Labels: docs, cleanup

## 5. Discovery Strict Mode Re-evaluation

- Title: Reassess default for discovery failure strictness
- Description: If false positives trend to zero in early v0.4.x usage, consider enabling strict mode by default (retain env escape hatch).
- Labels: testing, stability

## 6. Additional Loop Telemetry

- Title: Add exit code distribution summary & error pattern counts to loop summary
- Description: Aggregate per-iteration exit codes; optional histogram; maintain deterministic JSON ordering.
- Labels: telemetry, enhancement

## 7. HTML Diff Fragment Hardening

- Title: Add regression test for deterministic HTML list ordering & encoding
- Description: Introduce fixture test comparing two runs with controlled diffs to assert identical fragment bytes.
- Labels: tests, reliability

## 8. Percentile Strategy Documentation Deep Dive

- Title: Expand Streaming/Hybrid quantile accuracy docs with examples & tuning guidance
- Description: Provide empirical error bounds with sample sizes; clarify reconciliation tradeoffs.
- Labels: docs, performance

## 9. Runbook Automation Hooks

- Title: Auto-upload raw CLI artifacts in runbook script when under GitHub Actions
- Description: Detect `GITHUB_ACTIONS` and optionally emit artifact upload step summary guidance.
- Labels: automation, enhancement

## 10. CI Diagnostics Synthesis

- Title: Consolidate discovery, outcome, and aggregation hints into a single diagnostics report artifact
- Description: Compose structured JSON combining key signals for external dashboards.
- Labels: telemetry, enhancement

---
Generated: 2025-10-03
(Use this file as a staging area; remove or archive once issues are created.)
