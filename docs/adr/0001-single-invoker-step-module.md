<!-- markdownlint-disable-next-line MD041 -->
# ADR 0001 – Step-Based Pester Invoker Module

## Status

Accepted (2025-10-08)

## Context

We needed deterministic, observable Pester execution that cooperates with higher-level
automation. The legacy dispatcher owned the entire Unit/Integration loop, making it hard to
stream per-file results, enforce timeouts, or allow other orchestrators to schedule work.

## Decision

- Introduce `scripts/Pester-Invoker.psm1` exposing:
  - `New-PesterInvokerSession`
  - `Invoke-PesterFile`
  - `Complete-PesterInvokerSession`
- Execute each file in an isolated runspace (no nested `pwsh`).
- Emit crumbs (`pester-invoker/v1`): `plan`, `file-start`, `file-end`, `summary`.
- Store per-file results under `tests/results/pester/<slug>/pester-results.xml`.
- Keep `Invoke-PesterTests.ps1` backward compatible (`-SingleInvoker` imports the module and
  defers orchestration to the caller).

## Consequences

### Benefits

- Outer loops can control ordering, retries, diagnostics while sharing the invoker.
- Deterministic artefacts support dashboards/tests without parsing console output.
- Module is reusable by local runbooks and future CI steps.

### Trade-offs

- Slightly more complexity (runspace management).
- Callers must enforce category policy and aggregate results.

## References

- [`requirements/PESTER_SINGLE_INVOKER.md`](../requirements/PESTER_SINGLE_INVOKER.md)
- [`requirements/SINGLE_INVOKER_SYSTEM_DEFINITION.md`](../requirements/SINGLE_INVOKER_SYSTEM_DEFINITION.md)
- Implementation scripts: `scripts/Pester-Invoker.psm1`, `scripts/Invoke-PesterSingleLoop.ps1`
