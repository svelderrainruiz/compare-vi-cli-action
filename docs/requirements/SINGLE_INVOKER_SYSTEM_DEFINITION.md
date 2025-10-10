<!-- markdownlint-disable-next-line MD041 -->
# Requirement: Single Invoker System Definition

System-level behaviour for the step-based Pester invoker module.

## Components

- Invoker module (`Pester-Invoker.psm1`).
- Crumb writer (NDJSON to `_diagnostics/pester-invoker.ndjson`).
- Per-file artefact storage (`tests/results/pester/<slug>/`).

## Behaviour

- Each file invocation logs plan/start/end/summary events.
- Caller supplies category, include filters, retry logic.
- Session finalisation aggregates counts and failures for dashboards.

## Acceptance checks

- Crumb schema validated against `docs/schemas/pester-invoker-event.schema.json` (when added).
- Artefacts created/cleaned per file without cross-run leakage.
- Compatible with watcher/delta tooling.
