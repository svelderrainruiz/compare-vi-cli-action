<!-- markdownlint-disable-next-line MD041 -->
# Testing Patterns

Patterns for structuring Pester tests in this repository.

## Function shadowing

- Shadow helper functions inside `It {}` blocks when mocking external tools.
- Remove shadows at end of block to avoid leakage across tests.

## Categories & tagging

- Tag describes coverage: `Unit`, `Integration`, `Loop`, etc.
- Add requirement/ADR tags (`REQ:XYZ`, `ADR:0001`) for traceability matrix.

## Dispatcher behaviour

- Prefer the step-based invoker: `scripts/Pester-Invoker.psm1`.
- Use per-file `Invoke-PesterFile` for deterministic artefacts.
- Use `tools/Trace-PesterRun.ps1` to inspect crumbs.

## Skipping & retries

- Gate flaky tests via environment checks (`if (-not $env:RUN_FLAKY) { Skip }`).
- Use watcher options (`-RerunFailedAttempts`) for targeted reruns in local loops.

Further reading: [`docs/SCHEMA_HELPER.md`](./SCHEMA_HELPER.md), [`docs/TRACEABILITY_GUIDE.md`](./TRACEABILITY_GUIDE.md).
