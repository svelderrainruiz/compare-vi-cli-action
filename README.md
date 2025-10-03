# Compare VI (composite) GitHub Action

<!-- ci: bootstrap status checks -->

[![Validate](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/validate.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/validate.yml)
[![Smoke test](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/smoke.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/smoke.yml)
[![Test (mock)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/test-mock.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/test-mock.yml)
[![Marketplace](https://img.shields.io/badge/GitHub%20Marketplace-Action-blue?logo=github)](https://github.com/marketplace/actions/compare-vi-cli-action)

## Purpose

This repository provides a **composite GitHub Action** for comparing two LabVIEW `.vi` files
using National Instruments' LVCompare CLI tool. It enables CI/CD workflows to detect
differences between LabVIEW virtual instruments, making it easy to integrate LabVIEW code
reviews and diff checks into automated GitHub Actions workflows.

The action wraps the `LVCompare.exe` command-line interface with intelligent path
resolution, flexible argument pass-through, and structured output formats suitable for
workflow branching and reporting. It supports both single-shot comparisons and
experimental loop mode for latency profiling and stability testing.

**Key Features:**

- **Simple Integration**: Drop-in action for self-hosted Windows runners with LabVIEW installed
- **Flexible Configuration**: Full pass-through of LVCompare CLI flags via `lvCompareArgs`
- **Structured Outputs**: Exit codes, diff status, timing metrics, and command audit trails
- **CI-Friendly**: Automatic step summaries, JSON artifacts, and configurable fail-on-diff behavior
- **Loop Mode (Experimental)**: Aggregate metrics, percentile latencies, and histogram generation for performance analysis

Validated with LabVIEW 2025 Q3 on self-hosted Windows runners. See also:
[`CHANGELOG.md`](./CHANGELOG.md) and the release workflow at
`.github/workflows/release.yml`.

> **Breaking Change (v0.5.0)**: Legacy artifact names `Base.vi` / `Head.vi` are no longer supported. Use `VI1.vi` / `VI2.vi` exclusively. Public action input names (`base`, `head`) and environment variables (`LV_BASE_VI`, `LV_HEAD_VI`) remain unchanged.

## Requirements

- Self-hosted Windows runner with LabVIEW 2025 Q3 installed and licensed
- `LVCompare.exe` installed at the **canonical path**: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
- Only the canonical path is supported; paths via `PATH`, `LVCOMPARE_PATH`, or `lvComparePath` must resolve to this exact location

## Fixture Artifacts (VI1.vi / VI2.vi)

Two canonical LabVIEW VI files live at the repository root:

| File | Role |
|------|------|
| `VI1.vi` | Canonical base fixture |
| `VI2.vi` | Canonical head fixture |

Purpose:
 
- Fallback pair for examples, smoke workflows, and quick local validation.
- Guard test anchor ensuring legacy `Base.vi` / `Head.vi` names are not reintroduced.
- Stable targets for loop / latency simulation when no custom inputs provided.
- External dispatcher compatibility (LabVIEW-hosted tooling can intentionally evolve them in controlled commits).

Phase 1 Policy (enforced by tests & `tools/Validate-Fixtures.ps1`):
 
- Files MUST exist, be git-tracked, and be non-trivial in size (minimum enforced).
- Do not delete or rename them without a migration plan.
- Intentional content changes should include a rationale in the commit message (future phases may require a token such as `[fixture-update]`).

Phase 2 adds a hash manifest (`fixtures.manifest.json`) validated by `tools/Validate-Fixtures.ps1`.
If you intentionally change fixture contents, include `[fixture-update]` in the commit message and
regenerate the manifest via:

```powershell
pwsh -File tools/Update-FixtureManifest.ps1 -Allow
```

Without the token, hash mismatches fail validation (exit code 6). Manifest parse errors exit 7.

## Quick Start

### Basic Usage

```yaml
jobs:
  compare:
    runs-on: [self-hosted, Windows]
    steps:
      - uses: actions/checkout@v5
      - name: Compare VIs
        id: compare
  uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.4.1
        with:
          base: path/to/VI1.vi
          head: path/to/VI2.vi
          fail-on-diff: true

      - name: Act on result
        if: steps.compare.outputs.diff == 'true'
        shell: pwsh
        run: |
          Write-Host 'Differences detected.'
```

### Action Inputs

- `base` (required): Path to base `.vi` file
- `head` (required): Path to head `.vi` file
- `lvComparePath` (optional): Full path to `LVCompare.exe` if not on `PATH`
- `lvCompareArgs` (optional): Extra CLI flags for `LVCompare.exe` (space-delimited; quotes supported)
- `fail-on-diff` (optional, default `true`): Fail the job if differences are found
- `working-directory` (optional): Directory to run the command from; relative `base`/`head` are resolved from here
- `loop-enabled` (optional, default `false`): Enable experimental loop mode for performance testing

### Action Outputs

- `diff`: `true|false` whether differences were detected (0 = no diff, 1 = diff)
- `exitCode`: Raw exit code from the CLI
- `cliPath`: Resolved path to the executable
- `command`: Exact command line executed (quoted) for auditing
- `compareDurationSeconds`: Elapsed execution time (float, seconds)
- `compareDurationNanoseconds`: High-resolution elapsed time in nanoseconds
- `compareSummaryPath`: Path to JSON summary file (comparison metadata)
- `shortCircuitedIdentical`: `true|false` short‑circuit when `base` and `head` resolve identically (no process spawned)

Loop mode outputs (when `loop-enabled: true`): `iterations`, `diffCount`, `errorCount`,
`averageSeconds`, `totalSeconds`, `p50`, `p90`, `p99`, `quantileStrategy`,
`streamingWindowCount`, `loopResultPath`, `histogramPath`.

See [`docs/action-outputs.md`](./docs/action-outputs.md) for complete output documentation.

### Exit Codes and Behavior

- **Exit code mapping**: 0 = no diff, 1 = diff detected, any other code = failure
- **Identical path short-circuit**: If `base` and `head` resolve to the exact same absolute
  path, the action skips invoking LVCompare and emits
  `shortCircuitedIdentical=true`, `diff=false`, `exitCode=0`.
- **Same filename / different directories**: LVCompare cannot compare two different VIs
  with the *same leaf filename*. The action fails early with an explanatory error instead
  of triggering an IDE dialog.

### (Deprecated heading placeholder removed)

```yaml
  - name: Compare VIs
    id: compare
  uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.4.1
    with:
  base: VI1.vi
  head: VI1.vi  # Intentional identical path
      fail-on-diff: true

  - name: Handle identical-path short-circuit
    if: steps.compare.outputs.shortCircuitedIdentical == 'true'
    shell: pwsh
    run: |
      Write-Host 'Identical file comparison short-circuited; no diff expected.'

  - name: Handle real diff
    if: steps.compare.outputs.shortCircuitedIdentical != 'true' && steps.compare.outputs.diff == 'true'
    shell: pwsh
    run: |
      Write-Host 'Real differences detected.'
```

- **Always-emit outputs**: `diff`, `exitCode`, `cliPath`, `command` are always emitted
  even when the step fails, to support workflow branching and diagnostics.
- **Step summary**: A structured run report is appended to `$GITHUB_STEP_SUMMARY` with
  working directory, resolved paths, CLI path, command, exit code, and diff result.

## Advanced Configuration

For advanced configuration including lvCompareArgs recipes, working-directory usage, path resolution, and HTML report generation, see the **[Usage Guide](./docs/USAGE_GUIDE.md)**.

## Loop Mode

The action supports an experimental loop mode for performance testing and stability analysis. For complete details on loop mode, percentile strategies, histogram generation, and the autonomous runner script, see the **[Loop Mode Guide](./docs/COMPARE_LOOP_MODULE.md)**.

**Quick example:**

```yaml
- name: Performance test loop
  uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.4.1
  with:
    base: VI1.vi
    head: VI2.vi
    loop-enabled: true
    loop-max-iterations: 100
    loop-interval-seconds: 0.1
    fail-on-diff: false
```

Loop mode outputs include: `iterations`, `diffCount`, `errorCount`, `averageSeconds`, `totalSeconds`, `p50`, `p90`, `p99`, and more.

### Autonomous Integration Loop Runner

```powershell
$env:LV_BASE_VI = 'VI1.vi'
$env:LV_HEAD_VI = 'VI2.vi'
$env:LOOP_SIMULATE = '1'
$env:LOOP_DIFF_SUMMARY_FORMAT = 'Html'
$env:LOOP_MAX_ITERATIONS = '15'
$env:LOOP_SNAPSHOT_EVERY = '5'
$env:LOOP_JSON_LOG = 'loop-events.ndjson'
$env:LOOP_EMIT_RUN_SUMMARY = '1'
pwsh -File scripts/Run-AutonomousIntegrationLoop.ps1
```

Excerpt output:

```text
=== Integration Compare Loop Result ===
VI1: VI1.vi
VI2: VI2.vi
Iterations: 15 (Diffs=15 Errors=0)
Latency p50/p90/p99: 0.005/0.006/0.007 s
Diff summary fragment emitted.
Run summary JSON: loop-run-summary.json
Snapshots NDJSON: loop-snapshots.ndjson
```

Structured events sample (`loop-events.ndjson` first lines):

```jsonc
{"timestamp":"2025-10-01T12:00:00.100Z","type":"plan","simulate":true,"dryRun":false,"maxIterations":15,"interval":0,"diffSummaryFormat":"Html"}
{"timestamp":"2025-10-01T12:00:00.250Z","type":"result","iterations":15,"diffs":15,"errors":0,"succeeded":true}
```

Event schema versioning:

- Each event now includes `"schema":"loop-script-events-v1"`.
- Meta events:
  - `type=meta action=create` on new log creation
  - `type=meta action=rotate` when rotation occurs (fields: `from`, `to`)
- Backward compatibility: future minor additions will retain existing fields; consumers should ignore unknown properties.

JSON Schemas:

- `docs/schemas/loop-script-events-v1.schema.json`
- `docs/schemas/loop-final-status-v1.schema.json`

Final status example minimal structure:

```jsonc
{
  "schema": "loop-final-status-v1",
  "timestamp": "2025-10-01T12:34:56.789Z",
  "iterations": 40,
  "diffs": 12,
  "errors": 0,
  "succeeded": true,
  "averageSeconds": 0.012,
  "totalSeconds": 0.55,
  "percentiles": { "p50": 0.010, "p90": 0.018, "p99": 0.024 },
  "histogram": [ { "Index":0, "Start":0, "End":1, "Count":40 } ],
  "diffSummaryEmitted": true,
  "basePath": "VI1.vi",
  "headPath": "VI2.vi"
}
```

GitHub Actions step example (simulated):

```yaml
  - name: Autonomous integration loop (simulated)
    shell: pwsh
    run: |
  $env:LV_BASE_VI = 'VI1.vi'
  $env:LV_HEAD_VI = 'VI2.vi'
      $env:LOOP_SIMULATE = '1'
      $env:LOOP_MAX_ITERATIONS = '30'
      $env:LOOP_INTERVAL_SECONDS = '0'
      $env:LOOP_DIFF_SUMMARY_FORMAT = 'Markdown'
      $env:LOOP_EMIT_RUN_SUMMARY = '1'
      pwsh -File scripts/Run-AutonomousIntegrationLoop.ps1
```

If `GITHUB_STEP_SUMMARY` is present and a diff summary is generated it is appended automatically.

Timing metrics

- Each invocation now records wall-clock execution time and surfaces it via:
  - Action output `compareDurationSeconds` (was `durationSeconds` in earlier versions)
  - Action output `compareDurationNanoseconds` (high-resolution; derived from Stopwatch ticks)
  - Step summary line `Duration (s): <value>`
  - Step summary line `Duration (ns): <value>`
  - PR comment and artifact workflow job summary include a combined line: `<seconds>s (<milliseconds> ms)` for quick readability
  - HTML report field (if you render a report via `Render-CompareReport.ps1` passing `-CompareDurationSeconds` or legacy alias `-DurationSeconds`)

Artifact publishing workflow

A dedicated workflow (`.github/workflows/compare-artifacts.yml`) runs the local action, generates:

- `compare-summary.json` (JSON metadata: base, head, exit code, diff, timing)
- `compare-report.html` (HTML summary rendered via `Render-CompareReport.ps1`)

and uploads them as artifacts. It also appends a timing block to the job summary:

```text
### Compare VI Timing

- Seconds: <seconds>

- Nanoseconds: <nanoseconds>
- Combined: <seconds>s (<ms> ms)
```

Use this workflow to retain comparison evidence on every push or pull request without failing the build on differences (it sets `fail-on-diff: false`).

Integration readiness

Use the helper script to assess prerequisites before enabling integration tests:

```powershell
./scripts/Test-IntegrationEnvironment.ps1 -JsonPath tests/results/integration-env.json
```

Exit code 0 means ready; 1 indicates missing prerequisites (non-fatal for CI gating).

Troubleshooting unknown exit codes

- The action treats 0 as no diff and 1 as diff. Any other exit code fails fast.
- Outputs are still set for diagnostics: `exitCode`, `cliPath`, `command`, and `diff=false`.
- Check $GITHUB_STEP_SUMMARY for a concise run report.

Smoke test workflow

- A manual workflow is provided at `.github/workflows/smoke.yml`.
- Trigger it with “Run workflow” and supply `base`, `head`, and optional `lvComparePath`/`lvCompareArgs`.
- It runs the local action (`uses: ./`) on a self-hosted Windows runner and prints outputs.

Marketplace

- Listing: [GitHub Marketplace listing](https://github.com/marketplace/actions/compare-vi-cli-action)
- After publication, keep the badge/link updated to the final marketplace URL and ensure the README usage references the latest tag.

Notes

## For Developers

For information on testing, building, documentation generation, and the release process, see the **[Developer Guide](./docs/DEVELOPER_GUIDE.md)**.

### Quick Links

- **Testing**: [Developer Guide - Testing](./docs/DEVELOPER_GUIDE.md#testing)
- **Building**: [Developer Guide - Building](./docs/DEVELOPER_GUIDE.md#building-and-documentation-generation)
- **Contributing**: [CONTRIBUTING.md](./CONTRIBUTING.md)

### Test Dispatcher JSON Summary

The test dispatcher emits a machine-readable JSON summary (schema v1.7.1) for integration with tooling and metrics. For complete documentation on the schema, optional blocks, and consumption guidance, see the [Developer Guide - Test Dispatcher Architecture](./docs/DEVELOPER_GUIDE.md#test-dispatcher-architecture).

The repository ships a PowerShell test dispatcher (`Invoke-PesterTests.ps1`) that emits
a machine‑readable JSON summary (`pester-summary.json`) for every run. This enables
downstream tooling (dashboards, PR annotations, quality gates) to consume stable fields
without scraping console text.

Schema files:

- Baseline (core fields) [`docs/schemas/pester-summary-v1_1.schema.json`](./docs/schemas/pester-summary-v1_1.schema.json)
- Current (adds optional context blocks) [`docs/schemas/pester-summary-v1_2.schema.json`](./docs/schemas/pester-summary-v1_2.schema.json)
- Latest (adds optional discovery block) [`docs/schemas/pester-summary-v1_5.schema.json`](./docs/schemas/pester-summary-v1_5.schema.json)

Validation tests:

- Baseline absence of optional blocks: [`tests/PesterSummary.Schema.Tests.ps1`](./tests/PesterSummary.Schema.Tests.ps1)
- Context emission (when opt-in flag used): [`tests/PesterSummary.Context.Tests.ps1`](./tests/PesterSummary.Context.Tests.ps1)

## Troubleshooting

For common issues including path resolution problems, exit code interpretation, performance tuning, and test environment setup, see the **[Troubleshooting Guide](./docs/TROUBLESHOOTING.md)**.

## Documentation

- **[Usage Guide](./docs/USAGE_GUIDE.md)** - Advanced configuration, lvCompareArgs recipes, path resolution
- **[Loop Mode Guide](./docs/COMPARE_LOOP_MODULE.md)** - Experimental loop mode for performance testing
- **[Developer Guide](./docs/DEVELOPER_GUIDE.md)** - Testing, building, and release process
- **[Troubleshooting Guide](./docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Integration Tests](./docs/INTEGRATION_TESTS.md)** - Running tests with real LabVIEW
- **[Testing Patterns](./docs/TESTING_PATTERNS.md)** - Advanced test design patterns
- **[E2E Testing Guide](./docs/E2E_TESTING_GUIDE.md)** - End-to-end testing strategies
- **[Self-Hosted CI Setup](./docs/SELFHOSTED_CI_SETUP.md)** - Setting up self-hosted runners

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

## Support and Contributing

For bug reports and feature requests, please use [GitHub Issues](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/issues).

For contributions, please read [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines and development workflow.
