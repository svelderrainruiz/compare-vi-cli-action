<!-- markdownlint-disable-next-line MD041 -->
# Requirement: Watcher Busy Loop

Detect cases where the log grows but no test progress markers appear.

## Behaviour

- Track bytes consumed vs live file size.
- Emit `[busy-watch]` and escalate to `[busy-suspect]` when thresholds exceeded.
- Support exit code `3` when `--exit-on-no-progress` is set.

## Parameters

- `--no-progress-seconds` – total allowed seconds without progress.
- Half threshold triggers `[busy-watch]`; full threshold triggers `[busy-suspect]`.
- Works alongside hang detection from live feed requirement.

## Acceptance

- Unit tests validate marker emission and exit codes.
- CI integration ensures watcher logs surface warnings in summaries.
