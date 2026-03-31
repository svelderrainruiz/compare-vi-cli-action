# Fork Lane Control Plane SRS

## Document Control

- System: Fork-lane local assurance control plane
- Version: `v0.1.0`
- Owner: `#2078`
- Status: Active

## Scope

- Purpose:
  Define the local control-plane requirements for the fork-lane audit surface and
  its assurance loop.
- In scope:
  Local fork-lane manifest structure, scoped audit surface construction,
  standards-guided assurance execution, and action-item generation.
- Out of scope:
  Upstream self-hosted execution, release publication, and fork-global policy
  outside the issue-scoped control plane.

## Stakeholders

| Role | Need | Priority |
| --- | --- | --- |
| Product | One auditable record of what the fork lane is supposed to prove | High |
| Engineering | Deterministic local assurance runs with actionable output | High |
| QA | Traceable linkage from requirements to tests and code refs | High |
| Operations | Clear fork-only versus upstream-mounted boundaries | High |

## Requirements

| ID | Requirement | Rationale | Fit Criterion | Verification |
| --- | --- | --- | --- | --- |
| REQ-2078-001 | The fork-lane assurance system shall build a scoped audit surface from an explicit manifest and preserve repo-relative paths in the copied bundle. | The audit must evaluate the design surface, not the whole repo. | Running `priority:fork-lane:assurance` produces a `surface-bundle/` that contains only manifest-declared paths and retains their relative structure. | `TEST-2078-001` |
| REQ-2078-002 | The fork-lane assurance system shall run both the fork-lane design audit and the local standards audit, then emit one combined report and summary. | Operator decisions should come from one combined assurance outcome. | `fork-lane-assurance-report.json` and `fork-lane-assurance-summary.md` are both written and summarize design and standards status together. | `TEST-2078-002` |
| REQ-2078-003 | The fork-lane control plane shall keep generic fork-only artifacts off the upstream integration branch unless they are intentionally mounted. | Fork experimentation must not silently become upstream truth. | The reusable fork-lane model remains on the fork branch, while upstream integration proofs mount only the intended service-model slices. | `TEST-2078-003` |
| REQ-2078-004 | The fork-lane assurance report shall translate unresolved audit findings into explicit action items with standards anchors. | The audit is only useful if it drives the next engineering moves. | When findings remain, the report records action items that reference the responsible standards families and evidence paths. | `TEST-2078-004` |

## Assumptions

- The local standards-review skill is installed and callable with `python3`.
- The fork lane remains a local-first proving surface for issue `#2078`.

## Constraints

- The fork assurance loop must stay local and deterministic.
- The fork-lane issue must not require a fork-side self-hosted runner.
