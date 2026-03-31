# Pester Service Model Release Procedure

## Purpose

Define how the Pester service-model subsystem moves from fork-lane design work
to an upstream-mounted proof baseline and, eventually, a promotable release
surface.

## Procedure

1. Run `npm run priority:fork-lane:assurance:pester-service-model`.
2. Review the generated assurance report and summary.
3. If action items remain, keep iterating on the fork packet and do not mount a
   new upstream proof slice.
4. If the packet is clean enough, mount only the intended workflow changes onto
   the upstream integration rail.
5. Compare the additive service-model proof against the monolithic gate.
6. Only after positive proof, advance a promotion slice on the upstream issue.

## Baseline Rule

- Fork packet baselines are local design baselines.
- Upstream integration mounts are proving baselines.
- Promotion to release truth requires explicit comparative proof.

## Status Accounting

- Status is recorded in the issues, fork-lane manifests, and assurance outputs.
- The baseline must retain both the requirements packet and the resulting
  receipts or summaries used to justify the move.
