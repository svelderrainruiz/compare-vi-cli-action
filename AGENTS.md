# Repository Guidelines

## Primary Directive

- Proactively work on issue #88 until closed. Treat it as the top priority for all edits, CI runs, and PRs.
- Auth context: the human driving this session is logged into GitHub with an admin token. You may assume privileged operations are allowed (labels, dispatch, merge/tag) when appropriate and safe.
- Default behavior: operate autonomously (within this repo) to advance #88, while keeping runs deterministic and CI green. Always link commits/PRs to `#88`.
- Immediate actions when starting a session:
  - Pull issue details and confirm open tasks, acceptance criteria, and related PRs.
  - Create/update a working branch (e.g., `issue/88-<brief-slug>`), push minimal changes, and dispatch CI.
  - Open or update a PR referencing `#88`, apply required labels, and monitor until green. Merge when acceptance is met.

## Project Structure

- `scripts/` PowerShell modules/shims for compare/report/orchestrators (prefer `Import-Module`; avoid dot-sourcing).
- `tools/` Utilities for validation, summaries, telemetry, and dispatch.
- `tests/` Pester v5 suites; use `$TestDrive` for temp files; tag as `Unit`/`Integration`.
- `.github/workflows/` CI pipelines (self‑hosted Windows for LVCompare; hosted for preflight/lint).
- `Invoke-PesterTests.ps1` Local dispatcher for running tests and writing results.

## Build, Test, Develop

- Unit tests: `./Invoke-PesterTests.ps1`
- Include Integration: `./Invoke-PesterTests.ps1 -IncludeIntegration true`
- Custom paths: `./Invoke-PesterTests.ps1 -TestsPath tests -ResultsPath tests/results`
- Filter files: `./Invoke-PesterTests.ps1 -IncludePatterns 'CompareVI.*'`
- Quick smoke: `./tools/Quick-DispatcherSmoke.ps1 -Keep`

## Coding Style

- PowerShell 7+, Pester v5+. Match surrounding indentation (2–4 spaces).
- Do not spawn nested `pwsh`; invoke in‑process. Launch external tools via `ProcessStartInfo` (hidden, `UseShellExecute=false`).
- Only interface with `LVCompare.exe` (canonical path under Program Files); do not launch `LabVIEW.exe` directly.
- Default CI posture is non‑interactive; avoid popups and prompts.

## Testing Guidelines

- Prefer inline function shadowing inside each `It {}` and remove it after the test.
- Keep integration tests isolated and slower; unit tests fast.
- Results live under `tests/results/` (e.g., `pester-summary.json`, `pester-results.xml`, `session-index.json`).

## Commit & PRs

- Scope commits narrowly; use descriptive messages and link issues.
- PRs should explain what/why, list affected workflows, and attach result paths or artifacts.
- CI must be green (lint + Pester). On Windows, verify no console popups and no lingering processes.

## Agent Notes (Pinned)

- One-shot invoker per job (ensure-invoker composite); guard snapshots include `node.exe` to diagnose terminal spikes.
- Workflows own timeboxing via job `timeout-minutes`; dispatcher has no implicit timeout. Optional `STUCK_GUARD=1` writes heartbeat/partial logs (notice-only).
- Self-hosted Windows is the only Windows variant for LVCompare; use hosted runners only for preflight/lint.

### Delay Language & Wait Etiquette

- "Brief delay" means ~90 seconds (up to 2 minutes). Use this when waiting for GitHub to propagate new workflow files or publish artifacts after job completion.
- Always embed the explicit wait hint in responses when asking a human to wait, e.g., "brief delay (~90 seconds)".

### Measuring Human Response Time

- Use `tools/Agent-Wait.ps1` to record wait windows around human responses.
- Start a wait when you inform the human you will pause (dot-source in the current pwsh session):
  - `. ./tools/Agent-Wait.ps1; Start-AgentWait -Reason 'workflow propagation' -ExpectedSeconds 90`
- When the human replies, end the wait and report the elapsed time:
  - `. ./tools/Agent-Wait.ps1; End-AgentWait`
- Artifacts are written to `tests/results/_agent/`:
  - `wait-marker.json` (start marker), `wait-last.json` (last result), `wait-log.ndjson` (append-only log)
- If running in GitHub Actions, both start and end steps append to the job summary automatically.

### Local Unit Test & Telemetry

- Run just the Agent-Wait unit test locally:
  - `pwsh -NoLogo -NoProfile -Command ". ./tools/Agent-Wait.ps1; Import-Module Pester; $c=New-PesterConfiguration; $c.Run.Path='tests/Agent-Wait.Tests.ps1'; $c.Output.Verbosity='Normal'; $c.Run.PassThru=$true; $r=Invoke-Pester -Configuration $c; \"Tests: total=$($r.TotalCount) passed=$($r.PassedCount) failed=$($r.FailedCount)\""`
- Expected telemetry (local):
  - The test uses `$TestDrive` for isolation; it does not write into the working tree.
  - If you use Start-AgentWait/End-AgentWait manually, artifacts are written under `tests/results/_agent/` (marker, last, log).
  - Standard Pester results (when running broader suites) are under `tests/results/` (`pester-summary.json`, `pester-results.xml`, `session-index.json`).

### Fast Path for #88

- Comment dispatch (on an open PR): `/run orchestrated strategy=single include_integration=true sample_id=<id>`
  - Backward‑compatible: `/run orchestrated single ...` still maps to strategy=single.
- Manual dispatch (CLI):
  - `pwsh -File tools/Dispatch-WithSample.ps1 ci-orchestrated.yml -Ref develop -Strategy single -IncludeIntegration true`
  - Use `-Strategy matrix` for parallel categories when runners are idle.
- Merge policy: when all required checks are green and #88 acceptance is satisfied, proceed to merge (admin token available).

## Workflow Maintenance (ruamel.yaml updater)

Use the Python-based updater only when you need consistent, mechanical edits across multiple workflows (preserving comments/formatting):

- Appropriate changes:
  - Add hosted Windows preflight note blocks.
  - Inject `session-index-post` steps (per job or matrix category).
  - Normalize Runner Unblock Guard placement/inputs.
  - Add/adjust pre‑init force_run gate wiring in self‑hosted Pester.

- Avoid it for one-off, semantic edits (e.g., changing job logic, needs graphs). In those cases, edit YAML manually and run `actionlint`.

- Prerequisites:
  - `python3 -m pip install ruamel.yaml`

- Dry run and apply:
  - Check: `python tools/workflows/update_workflows.py --check .github/workflows/ci-orchestrated.yml`
  - Write: `python tools/workflows/update_workflows.py --write .github/workflows/ci-orchestrated.yml`
  - Always validate after: `./bin/actionlint -color`

- Scope and PR hygiene:
  - Keep updater changes in small, focused PRs; include a summary of files touched and the transforms applied.
  - If the updater warns or skips a file, fall back to a manual edit and re-run `actionlint`.
