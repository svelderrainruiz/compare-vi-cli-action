<!-- markdownlint-disable-next-line MD041 -->
# Requirement: Pester Single Invoker

Expose a reusable invoker module so outer orchestrators control Pester execution.

## Objectives

- Provide session primitives (`New-PesterInvokerSession`, `Invoke-PesterFile`, `Complete-PesterInvokerSession`).
- Emit deterministic crumbs (`pester-invoker/v1`) for dashboards/tests.
- Allow per-file artefacts (`tests/results/pester/<slug>/pester-results.xml`).

## Constraints

- No nested `pwsh` processes; remain in-process using runspaces.
- Compatible with existing `Invoke-PesterTests.ps1` (backward compatibility switch).
- Must surface category policy (Unit/Integration) via caller.

## Validation

- Unit tests covering session lifecycle and crumb emission.
- Integration tests verifying artefacts and compatibility with watch mode.

See ADR [`docs/adr/0001-single-invoker-step-module.md`](../adr/0001-single-invoker-step-module.md).
