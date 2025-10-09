# Requirement: Live Pester Watcher Feed

## Identifier
- `REQ-WATCHER-LIVE-FEED`

## Summary
Provide a live telemetry tap for Pester dispatcher runs so developers can observe test progress, detect stalls, and capture diagnostics without waiting for workflow logs. The watcher must:

1. Stream new lines from `tests/results/pester-dispatcher.log` as soon as they are written (including rotations).
2. Emit summary snapshots when `tests/results/pester-summary.json` updates.
3. Surface idle warnings/hang suspicion markers with consumed vs live byte counts.
4. Support fail-fast mode that exits non-zero when a hang is suspected.

## Rationale
- Improves local developer experience while triaging hanging self-hosted runs.
- Enables faster feedback loops during agent hand-offs (issue #88).
- Supplies richer diagnostics for PR reviews without waiting for GitHub log buffering.

## Acceptance Tests
- `tests/Watcher.Live.Tests.ps1` — verifies the Node watcher streams log and summary updates in real time and surfaces hang suspicion with a fail-fast exit.

## Related Documents
- `README.md` — Live Pester Watcher quickstart commands.
- `docs/DEV_DASHBOARD_PLAN.md` — Live Watcher Tooling details.
- `docs/SESSION_LOCK_HANDOFF.md` — Guidance to capture watcher diagnostics during queue contention investigations.
