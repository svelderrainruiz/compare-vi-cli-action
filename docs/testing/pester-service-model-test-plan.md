# Pester Service Model Test Plan

## Overview

- Release or baseline:
  Pester service-model assurance packet `v0.1.0`
- Owner:
  `#2069` / fork-lane support on `#2078`
- Scope:
  Trusted routing, context receipts, readiness receipts, execution-only
  behavior, and evidence classification for the Pester service model

## Test Items

| Item | Type | Risk | Notes |
| --- | --- | --- | --- |
| `pester-service-model-workflow-contract.test.mjs` | Integration | High | Verifies the workflow split and core receipt/evidence obligations |
| `pester-service-model-quality-workflow-contract.test.mjs` | Integration | Medium | Verifies the coverage gate and docs link-check control-plane workflow |
| `pester-gate.yml` + trusted pilot routing | Workflow | High | Verifies admission and orchestration across layers |
| `Invoke-PesterTests.ps1` execution contract | Execution | High | Verifies the dispatcher remains the execution engine only |

## Entry Criteria

- The service-model workflows and contract test are in sync with the declared requirements.
- The fork assurance packet is updated for the changed control-plane baseline.

## Exit Criteria

- Workflow-contract tests pass.
- The local assurance packet completes.
- Any remaining action items are explicitly accepted before upstream mounting.

## Coverage Targets

| Metric | Target | Evidence |
| --- | --- | --- |
| Workflow contract coverage | All layer responsibilities represented | `tools/priority/__tests__/pester-service-model-workflow-contract.test.mjs` |
| Receipt coverage | Context, readiness, execution, and evidence all emit auditable artifacts | assurance report + integration runs |
| Classification coverage | blocked and defect outcomes remain distinguishable | evidence workflow outputs |
| Packet coverage gate | Retained `coverage.xml` and named PR coverage gate | `.github/workflows/pester-service-model-quality.yml` |

## Reporting

- CI artifacts:
  upstream integration runs plus local assurance outputs
- Test report location:
  `tools/priority/__tests__/pester-service-model-workflow-contract.test.mjs`
- Defect tracking link:
  `#2069` and `#2078`
