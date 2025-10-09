<!-- markdownlint-disable-next-line MD041 -->
# Traceability Matrix Plan

Brief outline for implementing requirement/ADR traceability reporting.

## Goals

- Map Pester tests to requirements (`docs/requirements/**`) and ADRs (`docs/adr/**`).
- Emit JSON + optional HTML summaries for CI artefacts.
- Highlight uncovered requirements/ADRs and per-test coverage.

## Implementation sketch

1. Extend single-loop dispatcher to gather tags/header comments.
2. Aggregate coverage data into `trace-matrix.json` (schema `trace-matrix/v1`).
3. Optionally render HTML with status chips and doc links.
4. Surface matrix artefacts in workflows (upload + PR summary hint).

## Validation

- Unit tests covering aggregation and HTML renderer.
- Schema validation via `tools/Invoke-JsonSchemaLite.ps1`.
- Manual spot-check: review HTML for gaps before enabling CI enforcement.

See [`docs/TRACEABILITY_GUIDE.md`](../TRACEABILITY_GUIDE.md) for usage once implemented.
