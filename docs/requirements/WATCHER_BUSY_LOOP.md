# Requirement: Busy Loop Detection for Watcher

## Identifier
- `REQ-WATCHER-BUSY-LOOP`

## Summary
Detect busy infinite loops in the Pester dispatcher where log output continues but no test progress is made. The watcher must:

1. Track progress markers (default: Pester `It` results and summary updates) and record the last time progress occurred.
2. Warn when the log grows without progress for longer than a configurable threshold.
3. Optionally fail fast by exiting with a distinct code when the threshold is exceeded.
4. Report whether bytes are still changing when a no-progress warning or failure is raised.

## Rationale
- Complements idle detection by catching runs that emit repetitive output yet never complete.
- Provides quicker diagnosis for self-hosted runners stuck in loops (issue #88 follow-up).
- Improves developer feedback loops in local smoke runs and VS Code workflows.

## Acceptance Tests
- `tests/Watcher.BusyLoop.Tests.ps1` — verifies the watcher emits busy-loop warnings and exits with the configured code when no progress occurs despite log churn.

## Related Documents
- `docs/requirements/WATCHER_LIVE_FEED.md`
- `README.md` (Live Pester Watcher section)
- `docs/DEV_DASHBOARD_PLAN.md` (Live Watcher Tooling)
