<!-- markdownlint-disable-next-line MD041 -->
# Requirement: Watcher Live Feed

Ensure the watcher streams dispatcher logs + summary updates in real time.

## Essentials

- Stream `pester-dispatcher.log` and `pester-summary.json` changes.
- Emit `[log]`, `[summary]`, `[hang-watch]`, `[busy-watch]` markers.
- Provide CLI flags (`--warn-seconds`, `--hang-seconds`, `--no-progress-seconds`).
- Support fail-fast exits (`--exit-on-hang`, `--exit-on-no-progress`).

## Outputs

- Console messages with timing (`live-bytes`, `consumed-bytes`).
- Optional status JSON (`watcher-status.json`) for dashboards.

## Validation

- Unit tests verifying log tailing, summary triggers, warning thresholds.
- Integration: run watcher in CI to confirm markers appear and fail-fast exits work.

See also [`docs/DEV_DASHBOARD_PLAN.md`](../DEV_DASHBOARD_PLAN.md) for telemetry usage.
