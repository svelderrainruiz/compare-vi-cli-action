# Fork Lane Control Plane Architecture

## Overview

- System: Fork-lane local assurance control plane
- Purpose:
  Provide a local-first control plane for issue-scoped fork-lane design work and
  standards-guided assurance.
- Scope:
  The manifest model, the scoped audit surface, the local assurance runner, and
  the issue-specific evidence set for `#2078`.

## Stakeholders And Concerns

| Stakeholder | Concern | Viewpoint |
| --- | --- | --- |
| Product | The fork lane needs a bounded proving surface with auditable intent. | Governance |
| Engineering | Local iteration must stay fast while still producing standards-grounded output. | Execution |
| QA | Findings need traceability from requirement to test artifact and code ref. | Verification |
| Operations | Fork-only control-plane work must not silently become upstream integration truth. | Configuration |

## Context View

- External actors:
  Operator running the local fork lane, GitHub issue `#2078`, and the local
  standards-review skill.
- Upstream systems:
  `upstream/develop`, mounted `integration/**` proofs, and issue `#2069`.
- Downstream systems:
  Fork-lane manifests, assurance reports, and subsequent remediation slices.

## Container View

| Container | Responsibility | Technology |
| --- | --- | --- |
| Fork-lane manifests | Declare the active fork, issue scope, and lifecycle state | YAML |
| Design audit engine | Validate the fork-lane model and emit standards-grounded findings | Node.js |
| Local assurance runner | Build the scoped bundle, invoke standards scan and score, and synthesize action items | Node.js + Python |
| Evidence artifacts | Preserve JSON/Markdown outputs for operator review | JSON, Markdown |

## Component View

| Component | Container | Responsibility |
| --- | --- | --- |
| `issue-2078.yaml` | Fork-lane manifests | Issue-specific instance record |
| `index.yaml` | Fork-lane manifests | Active lane register and reconciliation anchor |
| `fork-lane-design-audit.mjs` | Design audit engine | Structural model audit and issue-level action-item generation |
| `fork-lane-local-assurance-ci.mjs` | Local assurance runner | Scoped bundle materialization and standards-driven uplift report |
| `fork-lane-assurance-report.json` | Evidence artifacts | Combined design and standards status |

## Deployment View

- Environments:
  Local operator shell and fork worktree only.
- Nodes:
  Local filesystem, Node.js runtime, `python3`, and installed local skill files.
- Runtime dependencies:
  `js-yaml`, the `repo-standards-review` skill scripts, and the checked-in fork
  control-plane files.

## Correspondence And Rationale

- Requirement-to-component notes:
  `REQ-2078-001` maps to the audit-surface manifest and the bundle builder.
  `REQ-2078-002` maps to the local assurance runner and combined report.
  `REQ-2078-003` maps to the issue manifest and upstream mounting discipline.
  `REQ-2078-004` maps to both audit engines and their action-item outputs.
- Decision rationale:
  The architecture isolates fork-only design iteration from upstream integration
  proof while preserving one operator-readable assurance report.
- Known tradeoffs:
  The local assurance bundle is narrower than the full repository; that improves
  determinism but means the audit surface must be maintained intentionally.

## ADR Index

- ADR-2078: Local assurance should audit a scoped fork-lane bundle rather than the full repository.
