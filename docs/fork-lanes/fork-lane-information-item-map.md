# Fork Lane Information Item Map

## Scope

- Product or service:
  Fork-lane local assurance control plane
- Repository:
  `compare-vi-cli-action`
- Baseline:
  Issue `#2078` fork branch
- Owner:
  Issue `#2078`

## Information Items

| Item Type | Current Path | Owner | Trigger | Proving Evidence |
| --- | --- | --- | --- | --- |
| Plan | `docs/testing/fork-lane-test-plan.md` | Engineering | Audit-surface change | Local assurance confirms the plan remains part of the scoped bundle |
| Specification | `docs/requirements-fork-lane-srs.md` | Engineering | Requirement change | REQ IDs and fit criteria stay aligned with the issue intent |
| Report | `docs/fork-lanes/fork-lane-quality-report.md` | Engineering | Assurance rerun | Report links to the current audit outputs |
| Procedure | `docs/release-procedure-fork-lane.md` | Engineering | Mount or close decision | Procedure matches the actual fork-only to upstream-mount flow |
| Architecture | `docs/architecture/fork-lane-control-plane.md` | Engineering | Control-plane design change | Architecture views and ADR remain current |
| Traceability | `docs/rtm-fork-lane.csv` | Engineering | Requirement or test change | RTM still links REQ, TEST, and code refs |

## Notes

- The fork-lane control plane is intentionally issue-scoped.
- Generic fork-lane artifacts stay fork-side until an explicit upstream mount is chosen.
