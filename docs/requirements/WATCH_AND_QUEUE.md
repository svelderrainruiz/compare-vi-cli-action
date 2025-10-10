<!-- markdownlint-disable-next-line MD041 -->
# Requirement: Watch & Queue Visibility

Provide visibility into queue waits, agent hand-offs, and watcher output.

## Goals

- Record queue wait metadata (Agent-Wait artefacts, session-lock status).
- Surface watcher heartbeat / busy status in dashboards and summaries.
- Offer PR commands to re-run workflows with the same inputs.

## Implementation hints

- `tools/Agent-Wait.ps1` start/stop helpers, writing to `_agent/wait-*.json`.
- Dev Dashboard sections for queue telemetry and watcher status.
- Job summaries include rerun hint and stakeholder contacts.

## Validation

- Ensure workflow summary lists wait metrics when Agent-Wait artefacts exist.
- Verify Dev Dashboard displays queue trend and watcher status.
- Confirm `/run orchestrated ...` comment replies include monitoring links.
