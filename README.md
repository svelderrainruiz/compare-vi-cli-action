<!-- markdownlint-disable-next-line MD041 -->
# Compare VI GitHub Action

[![Validate][badge-validate]][workflow-validate]
[![Smoke][badge-smoke]][workflow-smoke]
[![Mock Tests][badge-mock]][workflow-test-mock]
[![Docs][badge-docs]][environment-docs]

[badge-validate]: https://img.shields.io/github/actions/workflow/status/LabVIEW-Community-CI-CD/compare-vi-cli-action/validate.yml?label=Validate
[workflow-validate]: https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/validate.yml
[badge-smoke]: https://img.shields.io/github/actions/workflow/status/LabVIEW-Community-CI-CD/compare-vi-cli-action/smoke.yml?label=Smoke
[workflow-smoke]: https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/smoke.yml
[badge-mock]: https://img.shields.io/github/actions/workflow/status/LabVIEW-Community-CI-CD/compare-vi-cli-action/test-mock.yml?label=Mock%20Tests
[workflow-test-mock]: https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/test-mock.yml
[badge-docs]: https://img.shields.io/badge/docs-Environment%20Vars-6A5ACD
[environment-docs]: ./docs/ENVIRONMENT.md

## Overview

This composite action runs NI **LVCompare** to diff two LabVIEW virtual instruments (`.vi`). It
supports PR checks, scheduled verification, and loop-style benchmarking while emitting
structured JSON artifacts and step summaries. The action is validated against **LabVIEW 2025
Q3** on self-hosted Windows runners.

> **Breaking change (v0.5.0)** – canonical fixtures are now `VI1.vi` / `VI2.vi`. Legacy names
> `Base.vi` / `Head.vi` are no longer published.

### Key capabilities

- Works on any self-hosted Windows runner with LVCompare installed.
- Exposes all LVCompare switches via the `lvCompareArgs` input.
- Produces machine-readable outputs (`compare-exec.json`, summaries, optional HTML).
- Bundles a watcher/telemetry toolkit to flag hangs, busy loops, and rogue processes.
- Includes an experimental loop mode for latency profiling.

## Quick start

```yaml
name: Compare LabVIEW VIs
on:
  pull_request:
    paths: ['**/*.vi']

jobs:
  compare:
    runs-on: [self-hosted, Windows, X64]
    steps:
      - uses: actions/checkout@v4
      - name: Run LVCompare
        uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@main
        with:
          base: fixtures/VI1.vi
          head: fixtures/VI2.vi
```

### Prerequisites

- LabVIEW (and LVCompare) installed on the runner. Default path:
  `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`.
- The repository checkout includes or generates the `.vi` files to compare.

## Monitoring & telemetry

### Dev dashboard

```powershell
pwsh ./tools/Dev-Dashboard.ps1 `
  -Group pester-selfhosted `
  -ResultsRoot tests/results `
  -Html `
  -Json
```

This command renders a local snapshot of session-lock heartbeat age, queue wait trends, and
DX reminders. Workflows call `tools/Invoke-DevDashboard.ps1` to publish HTML/JSON artifacts.

### Live watcher

- `npm run watch:pester` (warn 90 s, hang 180 s).
- `npm run watch:pester:fast:exit` (warn 60 s, hang 120 s, exits on hang).
- `npm run dev:watcher:ensure` / `status` / `stop` (persistent watcher lifecycle).
- `npm run dev:watcher:trim` (rotates `watch.out` / `watch.err` when >5 MB or ~4,000 lines).
- `tools/Print-AgentHandoff.ps1 -AutoTrim` (prints summary and trims automatically when
  `needsTrim=true`).

Status JSON contains `state`, heartbeat freshness, and byte counters – ideal for hand-offs or
CI summaries.

## Bundled workflows

- **Validate** – end-to-end self-hosted validation (fixtures, LVCompare, Pester suites).
- **Smoke** – minimal regression guard for documentation-only changes.
- **Fixture Drift** – verifies fixture manifests and retains comparison evidence.
- **VI Binary Gate** – ensures LabVIEW binaries remain normalized.
- **Markdownlint** – runs `npm run lint:md:changed` with the trimmed configuration below.

Explore `.github/workflows` for matrices, inputs, and dispatch helpers.

## Markdown lint

`markdownlint` is configured to allow up to 120 columns (tables, code fences, headings
excluded) and to downgrade MD041 while legacy docs are cleaned. Generated artifacts are
ignored via `.markdownlintignore`.

Lint changed files locally:

```powershell
npm run lint:md:changed
```

## Documentation map

| Topic | Location |
| ----- | -------- |
| Action usage | `docs/USAGE_GUIDE.md` |
| Fixture drift | `docs/FIXTURE_DRIFT.md` |
| Loop mode | `docs/COMPARE_LOOP_MODULE.md` |
| Integration runbook | `docs/INTEGRATION_RUNBOOK.md` |
| Troubleshooting | `docs/TROUBLESHOOTING.md` |
| Traceability (requirements ↔ tests) | `docs/TRACEABILITY_GUIDE.md` |

## Contributing

1. Branch from `develop`, run `npm ci`.
2. Execute tests (`./Invoke-PesterTests.ps1` or watcher-assisted workflows).
3. Lint (`npm run lint:md:changed`, `tools/Check-ClangFormat.ps1` if relevant).
4. Submit a PR referencing **#88** and include rationale plus artifacts.

Follow `AGENTS.md` for coding etiquette and keep CI deterministic. Large workflow updates
should note affected jobs and link to supporting ADRs.

### Local validation matrix

Run the commands below (or invoke the matching VS Code task) before pushing. Each entry calls the same automation that our workflows execute, so local runs mirror CI behaviour.

| Command / Run Task | Script invoked | Mirrors CI job(s) | Notes |
| --- | --- | --- | --- |
| `pwsh -File tools/PrePush-Checks.ps1` / “Run PrePush Checks” | `tools/PrePush-Checks.ps1` | `validate.yml › lint` | Runs actionlint, markdownlint, tracked-artifact guard, rerun-hint helper, watcher schema validation. |
| `pwsh ./Invoke-PesterTests.ps1` / “Run Pester Tests (Unit)” | `Invoke-PesterTests.ps1` | Unit consumers in `validate.yml` | Fast feedback on unit suites before dispatching orchestrated runs. |
| `pwsh ./Invoke-PesterTests.ps1 -IncludeIntegration true` / “Run Pester Tests (Integration)” | `Invoke-PesterTests.ps1 -IncludeIntegration true` | Integration phase in `ci-orchestrated.yml` and smoke stages in `validate.yml` | Requires LVCompare; runs the same categories the orchestrated pipeline executes. |
| “Run Non-LV Checks (Tools Image)” | `tools/Run-NonLVChecksInDocker.ps1 -ToolsImageTag comparevi-tools:local -UseToolsImage` | `validate.yml › cli-smoke` non-LV preflight | Uses the consolidated tools image so actionlint/markdownlint/docs drift checks match the smoke job environment. |
| “Run Non-LV Checks (Docker)” | `tools/Run-NonLVChecksInDocker.ps1` | `validate.yml › cli-smoke` fallback path | Falls back to per-tool containers when the unified image is unavailable. |
| “Integration (Standing Priority): Auto Push + Start + Watch” | `tools/Start-IntegrationGated.ps1 -AutoPush -Start -Watch` | `ci-orchestrated.yml` standing-priority dispatcher + watcher | Pushes with the admin token, resolves issue [#127](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/issues/127), dispatches, then streams logs via Docker watcher. |

Keeping these green locally prevents surprises when Validate or the orchestrated pipeline runs in CI.

#### Multi-plane hook helpers

#### Standing priority helpers

- `npm run priority:bootstrap` — run hook preflight/parity (optional via `-- -VerboseHooks`) and refresh the standing-priority snapshot/router.
- `npm run priority:handoff` — import the latest handoff summaries into the current PowerShell session (globals such as `$StandingPrioritySnapshot` and `$StandingPriorityRouter`).
- `npm run priority:release` — simulate the release path from the router; add `-- -Execute` to run `Branch-Orchestrator.ps1 -Execute` instead of the default dry-run.
 — simulates release prep using the current router; pass  to run  after the dry-run.


- `npm run hooks:plane` — prints the detected plane (for example `windows-pwsh`, `linux-wsl`, `github-ubuntu`) and the active enforcement mode.
- `npm run hooks:preflight` — verifies Node/PowerShell availability for the current plane and warns if a dependency is missing.
- `npm run hooks:multi` — runs both the shell and PowerShell wrappers, publishes labelled summaries (`tests/results/_hooks/pre-commit.shell.json`, etc.), and fails when the JSON differs.
- `npm run hooks:schema` — validates all hook summaries against `docs/schemas/hooks-summary-v1.schema.json`.

Tune behaviour with `HOOKS_ENFORCE=fail|warn|off` (default: `fail` in CI, `warn` locally). Use `HOOKS_PWSH` or `HOOKS_NODE` to point at custom executables when bouncing between planes.

## Support & feedback

- File issues: <https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/issues>
- Contact NI for LabVIEW licensing questions.
- For agent coordination, follow the steps in `AGENT_HANDOFF.txt`.
