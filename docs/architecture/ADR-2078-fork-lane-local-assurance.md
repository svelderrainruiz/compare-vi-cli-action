# ADR-2078: Scoped Local Assurance For Fork Lanes

## Status

Accepted

## Context

Issue `#2078` needs a local-first assurance loop for the fork-lane control
plane. A full-repository standards scan is too broad and too slow for that
issue-specific design surface, while a fork-only structural audit is too narrow
to surface requirements, architecture, CM, testing, and documentation debt.

## Decision

Use a scoped local assurance bundle declared by
`tools/priority/fork-lanes/audit-surface.yaml`.

The local assurance runner:
- materializes the scoped bundle
- runs the fork-lane design audit on the real worktree
- runs the local standards scan and score on the bundle
- emits one combined report with action items

## Rationale

- The fork lane needs architecture rationale, not only schema validation.
- The operator needs one action-oriented output instead of separate audit
  artifacts.
- The fork branch is the right proving surface for generic control-plane design
  artifacts before any intentional upstream mount.

## Consequences

- The audit surface must be maintained when the fork-lane control plane changes.
- The assurance loop becomes fast enough to rerun locally during issue work.
- Upstream integration mounts remain explicit and smaller.
