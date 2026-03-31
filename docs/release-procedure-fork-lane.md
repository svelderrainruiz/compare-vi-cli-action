# Fork Lane Release Procedure

## Purpose

Describe how the fork-lane control plane moves from local draft work to a
stable, reviewable baseline.

## Procedure

1. Run `npm run priority:fork-lane:audit`.
2. Run `npm run priority:fork-lane:assurance`.
3. Review `fork-lane-assurance-report.json` and `fork-lane-assurance-summary.md`.
4. If action items remain, keep the fork-lane change on the fork branch.
5. If the assurance packet is clean enough for mounting, document that decision
   on issue `#2078` and then mount only the intended slice onto the upstream
   integration branch.

## Baseline Rule

- The fork branch is the baseline until an upstream mount is explicitly chosen.
- The assurance packet for the selected baseline must remain reproducible from
  the checked-in audit surface.

## Status Accounting

- Status accounting is tracked in `index.yaml`, the issue manifest, and the
  local assurance outputs.
- Change control for this procedure follows the CM plan.
