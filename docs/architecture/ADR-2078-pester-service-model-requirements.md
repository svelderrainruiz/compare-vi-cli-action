# ADR-2078-PSM-001: Specify The Pester Service Model As A Layered Subsystem

## Status

Accepted

## Context

The current Pester pilot already separates routing, context, readiness,
execution, and evidence, but those obligations still live mainly in workflow
files and workflow-contract tests. That makes the subsystem executable, but not
yet fully specified or traceable as a control plane.

## Decision

Create a dedicated assurance packet for the Pester service model with:
- an SRS
- an RTM
- an architecture packet
- a CM plan and release procedure
- a test plan
- an information-item map
- a scoped local assurance surface on the fork

## Rationale

- Requirements should describe stable obligations, not just test behavior.
- Tests should verify the subsystem contract instead of acting as the contract.
- The fork is the correct place to specify and audit the subsystem before
  deciding what to mount upstream.

## Consequences

- The service-model packet can now be audited locally with the same assurance
  runner used for other fork-lane control planes.
- Remaining gaps become explicit action items instead of ambient workflow debt.
- Promotion to upstream can be argued from requirements and receipts, not just
  from observed workflow behavior.
