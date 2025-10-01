# Compare VI (composite) GitHub Action

<!-- ci: bootstrap status checks -->

[![Validate](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/validate.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/validate.yml)
[![Smoke test](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/smoke.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/smoke.yml)
[![Test (mock)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/test-mock.yml/badge.svg)](https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/actions/workflows/test-mock.yml)
[![Marketplace](https://img.shields.io/badge/GitHub%20Marketplace-Action-blue?logo=github)](https://github.com/marketplace/actions/compare-vi-cli-action)

Diff two LabVIEW `.vi` files using NI LVCompare CLI. Validated with LabVIEW 2025 Q3 on self-hosted Windows runners.

See also: [`CHANGELOG.md`](./CHANGELOG.md) and the release workflow at `.github/workflows/release.yml`.

Requirements

- Self-hosted Windows runner with LabVIEW 2025 Q3 installed and licensed
- `LVCompare.exe` installed at the **canonical path**: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
- Only the canonical path is supported; paths via `PATH`, `LVCOMPARE_PATH`, or `lvComparePath` must resolve to this exact location

Inputs

- `base` (required): Path to base `.vi`
- `head` (required): Path to head `.vi`
- `lvComparePath` (optional): Full path to `LVCompare.exe` if not on `PATH`
- `lvCompareArgs` (optional): Extra CLI flags for `LVCompare.exe` (space-delimited; quotes supported)
- `fail-on-diff` (optional, default `true`): Fail the job if differences are found
- `working-directory` (optional): Directory to run the command from; relative `base`/`head` are resolved from here

Outputs

- `diff`: `true|false` whether differences were detected (based on exit code mapping 0=no diff, 1=diff)
- `exitCode`: Raw exit code from the CLI
- `cliPath`: Resolved path to the executable
- `command`: The exact command line executed (quoted) for auditing
- `compareDurationSeconds`: Elapsed execution time (float, seconds) for the LVCompare invocation (renamed from `durationSeconds`)
- `compareDurationNanoseconds`: High-resolution elapsed time in nanoseconds (useful for profiling very fast comparisons)

Exit codes and step summary

- Exit code mapping: 0 = no diff, 1 = diff detected, any other code = failure.
- Outputs (`diff`, `exitCode`, `cliPath`, `command`) are always emitted even when the step fails, to support branching and diagnostics.
- A structured run report is appended to `$GITHUB_STEP_SUMMARY` with working directory, resolved paths, CLI path, command, exit code, and diff result.

Usage (self-hosted Windows)

```yaml
jobs:
  compare:
    runs-on: [self-hosted, Windows]
    steps:
      - uses: actions/checkout@v5
      - name: Compare VIs
        id: compare
        uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.2.0
        with:
          working-directory: subfolder/with/vis
          base: relative/path/to/base.vi   # resolved from working-directory if set
          head: relative/path/to/head.vi   # resolved from working-directory if set
          # Canonical path is enforced - set via LVCOMPARE_PATH env or omit if CLI is at canonical location
          # lvComparePath: C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe
          # Optional extra flags (space-delimited, quotes supported)
          lvCompareArgs: "--some-flag --value \"C:\\Temp\\My Folder\\file.txt\""
          # Built-in policy: fail on diff by default
          fail-on-diff: "true"

      - name: Act on result
        if: steps.compare.outputs.diff == 'true'
        shell: pwsh
        run: |
          Write-Host 'Differences detected.'
```

UNC/long path guidance

- The action resolves `base`/`head` to absolute paths before invoking LVCompare.
- If you encounter long-path or UNC issues, consider:
  - Using shorter workspace-relative paths via `working-directory`.
  - Mapping a drive on self-hosted runners for long UNC prefixes.
  - Ensuring your LabVIEW/Windows environment supports long paths.

Common lvCompareArgs recipes (patterns)

For comprehensive documentation on LVCompare CLI flags and Git integration, see [`docs/knowledgebase/LVCompare-Git-CLI-Guide_Windows-LabVIEW-2025Q3.md`](./docs/knowledgebase/LVCompare-Git-CLI-Guide_Windows-LabVIEW-2025Q3.md).

**Recommended noise filters** (reduce cosmetic diff churn):

- `lvCompareArgs: "-nobdcosm -nofppos -noattr"`
  - `-nobdcosm` - Ignore block diagram cosmetic changes (position/size/appearance)
  - `-nofppos` - Ignore front panel object position/size changes
  - `-noattr` - Ignore VI attribute changes

**LabVIEW version selection:**

- `lvCompareArgs: '-lvpath "C:\\Program Files\\National Instruments\\LabVIEW 2025\\LabVIEW.exe"'`

**Other common patterns:**

- Pass a path with spaces:
  - `lvCompareArgs: "--flag \"C:\\Path With Spaces\\out.txt\""`
- Multiple flags:
  - `lvCompareArgs: "--flag1 value1 --flag2 value2"`
- Environment-driven values:
  - `lvCompareArgs: "--flag \"${{ runner.temp }}\\out.txt\""`

HTML Comparison Reports

For CI/CD pipelines and code reviews, you can generate HTML comparison reports using **LabVIEWCLI** (requires LabVIEW 2025 Q3 or later):

```powershell
# Generate single-file HTML report
LabVIEWCLI -OperationName CreateComparisonReport `
  -vi1 "path\to\base.vi" -vi2 "path\to\head.vi" `
  -reportType HTMLSingleFile -reportPath "CompareReport.html" `
  -nobdcosm -nofppos -noattr
```

**Benefits:**

- Self-contained HTML file suitable for artifact upload
- Visual diff output for code reviews
- Works with recommended noise filter flags
- Can be integrated into workflows for automated comparison reporting

See the knowledgebase guide for more details on HTML report generation.

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

- This action maps `LVCompare.exe` exit codes to a boolean `diff` (0 = no diff, 1 = diff). Any other exit code fails the step.
- **Canonical path policy**: Only `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe` is supported
- Any `lvComparePath` or `LVCOMPARE_PATH` value must resolve to this exact canonical path or the action will fail

Troubleshooting

- Ensure the runner user has the necessary LabVIEW licensing.
- Verify `LVCompare.exe` is installed at: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
- If you set `LVCOMPARE_PATH` or `lvComparePath`, ensure they point to the canonical path
- Check composite action outputs (`diff`, `exitCode`, `cliPath`, `command`) and the CLI exit code for diagnostics.
- **For comprehensive CI/CD setup and troubleshooting**, see [Self-Hosted Runner CI/CD Setup Guide](./docs/SELFHOSTED_CI_SETUP.md)

Tests

- Unit tests (no external CLI):
  - Run: `pwsh -File ./tools/Run-Pester.ps1`
  - Produces artifacts under `tests/results/` (NUnit XML and summary)
- Integration tests (requires canonical LVCompare path on self-hosted runner):
  - Run: `pwsh -File ./tools/Run-Pester.ps1 -IncludeIntegration`
  - Requires environment variables: `LV_BASE_VI` and `LV_HEAD_VI` pointing to test `.vi` files
  - See detailed prerequisites & skip behavior: [Integration Tests Guide](./docs/INTEGRATION_TESTS.md)
- CI workflows:
  - `.github/workflows/test-pester.yml` - runs unit tests on GitHub-hosted Windows runners
  - `.github/workflows/pester-selfhosted.yml` - runs integration tests on self-hosted runners with real CLI
  - `.github/workflows/pester-diagnostics-nightly.yml` - nightly synthetic failure to validate enhanced diagnostics (non-blocking)
  - Use PR comments to trigger: `/run unit`, `/run mock`, `/run smoke`, `/run pester-selfhosted`
- **For end-to-end testing**, see [End-to-End Testing Guide](./docs/E2E_TESTING_GUIDE.md)

Integration compare control loop (developer scaffold)

For rapid, iterative development against two real VIs (e.g. editing a feature branch VI and observing diff stability / timing) a lightweight polling loop script is provided:

```powershell
pwsh -File ./scripts/Integration-ControlLoop.ps1 `
  -Base 'C:\repos\main\ControlLoop.vi' `
  -Head 'C:\repos\feature\ControlLoop.vi' `
  -LvCompareArgs "-nobdcosm -nofppos -noattr" `
  -SkipIfUnchanged `
  -IntervalSeconds 3
```

Key features:

- Enforces canonical LVCompare path only
- Polls at a configurable interval (default 5s)
- Optional skip when neither VI timestamp changed (`-SkipIfUnchanged`)
- Shows a compact per-iteration table (diff flag, exit code, duration)
- Records timing metrics and counts (diffs, errors)
- Optional JSON lines log via `-JsonLog path\loop-log.jsonl`
- Optional `-FailOnDiff` to terminate on first diff (useful in guard scenarios)

Example JSON log line (one per iteration when `-JsonLog` supplied):

```jsonc
{
  "iteration": 4,
  "timestampUtc": "2025-10-01T12:34:56.789Z",
  "skipped": false,
  "diff": true,
  "exitCode": 1,
  "status": "OK",
  "durationSeconds": 0.217,
  "baseChanged": false,
  "headChanged": true
}
```

Planned extensions (contributions welcome): file system watcher trigger, HTML report generation on diff, latency histogram, automatic re-baselining.

Module reuse

The loop logic is also packaged as a lightweight module for programmatic automation: `module/CompareLoop/CompareLoop.psd1`.

Example:

```powershell
Import-Module ./module/CompareLoop/CompareLoop.psd1 -Force
$exec = { param($CliPath,$Base,$Head,$Args) 0 } # always no diff
Invoke-IntegrationCompareLoop -Base 'C:\repos\main\ControlLoop.vi' -Head 'C:\repos\feature\ControlLoop.vi' -MaxIterations 1 -CompareExecutor $exec -BypassCliValidation -SkipValidation -PassThroughPaths -Quiet
```

## Composite Action Loop Mode (Experimental)

The composite action now supports an optional **loop mode** (`loop-enabled: true`) that delegates to the `CompareLoop` module to collect multiple LVCompare iterations and export aggregate latency metrics, percentiles, and (optionally) a histogram.

When loop mode is enabled, the action:

1. Executes up to `loop-max-iterations` iterations (or fewer if canceled / job ends).
2. Uses a simulated executor by default (`loop-simulate: true`) so percentile telemetry can run on GitHub-hosted runners without LabVIEW installed. Set `loop-simulate: false` to run real comparisons (requires canonical CLI path).
3. Emits additional outputs for downstream workflows (average latency, p50/p90/p99, counts, reservoir window size, etc.).
4. Writes a `compare-loop-summary.json` (aggregate) and optional histogram JSON file into the runner temp directory.

### Loop Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `loop-enabled` | `false` | Enable loop mode branch. |
| `loop-max-iterations` | `25` | Cap on iterations (0 = run until diff only if `fail-on-diff` is false; otherwise treat as finite). |
| `loop-interval-seconds` | `0` | Delay between iterations (fractional seconds supported). |
| `quantile-strategy` | `StreamingReservoir` | `Exact` \| `StreamingReservoir` \| `Hybrid`. |
| `stream-capacity` | `500` | Reservoir capacity (min 10). |
| `reconcile-every` | `0` | Reservoir rebuild cadence (0 = disabled). |
| `hybrid-exact-threshold` | `200` | Exact seed iterations before streaming when `Hybrid` is chosen. |
| `histogram-bins` | `0` | Number of histogram bins (0 = disabled). |
| `loop-simulate` | `true` | Use internal mock executor instead of real LVCompare. |
| `loop-simulate-exit-code` | `1` | Exit code from simulated executor (1=differences, 0=no diff). |

### Loop Outputs

| Output | Meaning |
|--------|---------|
| `iterations` | Total iterations executed. |
| `diffCount` | Number of diff iterations (exit code 1). |
| `errorCount` | Unexpected error iterations. |
| `averageSeconds` | Mean duration across non-skipped iterations. |
| `totalSeconds` | Total elapsed wall clock (s). |
| `p50` / `p90` / `p99` | Latency percentiles (seconds). Blank if insufficient samples. |
| `quantileStrategy` | Effective quantile strategy used (alias normalized). |
| `streamingWindowCount` | Active reservoir sample count (streaming modes). |
| `loopResultPath` | Path to loop summary JSON (`loop-summary-v1` schema). |
| `histogramPath` | Path to histogram JSON (if bins > 0, else blank). |

Legacy single-run outputs (`diff`, `exitCode`, `compareDurationSeconds`, etc.) are still populated for compatibility (duration fields represent average loop latency when in loop mode).

### Example: Simulated Loop With Streaming Reservoir

```yaml
jobs:
  perf-probe:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v5
      - name: Simulated latency loop
        id: loop
        uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.3.0
        with:
          base: Base.vi
          head: Head.vi
          loop-enabled: true
          loop-max-iterations: 40
          loop-interval-seconds: 0
          quantile-strategy: StreamingReservoir
          stream-capacity: 400
          reconcile-every: 0
          histogram-bins: 5
          loop-simulate: true
          loop-simulate-exit-code: 1
      - name: Print percentiles
        run: |
          echo "p50=${{ steps.loop.outputs.p50 }} p90=${{ steps.loop.outputs.p90 }} p99=${{ steps.loop.outputs.p99 }}"
```

### Example: Hybrid Strategy With Reconciliation (Real CLI)

```yaml
jobs:
  soak:
    runs-on: [self-hosted, Windows]
    steps:
      - uses: actions/checkout@v5
      - name: Hybrid percentile soak
        id: loop
        uses: LabVIEW-Community-CI-CD/compare-vi-cli-action@v0.3.0
        with:
          base: path/to/base.vi
          head: path/to/head.vi
          fail-on-diff: "false"            # keep iterating even if diffs occur
          loop-enabled: true
          loop-max-iterations: 2000
          loop-interval-seconds: 0
          quantile-strategy: Hybrid
          hybrid-exact-threshold: 300
          stream-capacity: 600
          reconcile-every: 1800
          histogram-bins: 6
          loop-simulate: false             # real comparisons
```

Loop JSON summary schema (`loop-summary-v1`):

```jsonc
{
  "iterations": 40,
  "diffCount": 18,
  "errorCount": 0,
  "averageSeconds": 0.012,
  "totalSeconds": 0.51,
  "quantileStrategy": "StreamingReservoir",
  "streamingWindowCount": 400,
  "percentiles": { "p50": 0.010, "p90": 0.018, "p99": 0.025 },
  "histogram": [ { "Index":0, "Start":0, "End":1, "Count":15 } ],
  "schema": "loop-summary-v1",
  "generatedUtc": "2025-10-01T12:34:56.789Z"
}
```

Guidance:

- Use `StreamingReservoir` for long / memory-sensitive runs; adjust `stream-capacity` if p99 unstable.
- Use `Hybrid` when early exact percentiles are important before switching to bounded memory.
- Add `reconcile-every` for multi-thousand iteration soaks to minimize drift in non-stationary distributions.
- Keep `loop-simulate: true` in public CI if LabVIEW licenses aren't available; switch to `false` only on trusted self-hosted runners.

Limitations:

- Histogram is coarse (equal-width); future enhancements may provide adaptive or log-scale bucketing.
- Percentiles are limited to p50/p90/p99 (custom list planned as a future enhancement).
- Loop mode intentionally does not expose raw per-iteration records via outputs—consume the JSON file if needed.


## Streaming quantile strategies (timing distribution)

The compare loop module can estimate latency percentiles (p50/p90/p99) with bounded memory.

Supported `-QuantileStrategy` values:

| Strategy | Behavior | Memory | Notes |
|----------|----------|--------|-------|
| `Exact` | Collects all non-zero iteration durations then sorts at the end | O(N) | Most accurate; can grow large for long runs |
| `StreamingReservoir` | Maintains a fixed-size ring buffer (reservoir) of recent samples | O(K) | Formerly named `StreamingP2`; provides rolling approximation |
| `Hybrid` | Starts as `Exact` for seeding, then switches to `StreamingReservoir` after threshold | O(K)+O(T) initially | Good balance of early accuracy + steady-state bounded memory |

Additional parameters:

- `-StreamCapacity <int>`: Reservoir size (default 500, minimum 10). Larger improves tail stability but increases memory and sort cost per percentile snapshot.
- `-HybridExactThreshold <int>`: Number of iterations to collect exact samples before switching in `Hybrid`.
- `-ReconcileEvery <int>`: If > 0 and streaming active, periodically rebuilds the reservoir from all collected durations using a uniform stride subsample. Helps reduce drift in long, highly non-stationary runs. Set to a multiple of `StreamCapacity` (e.g. capacity 500, reconcile every 2000 iterations) for a balance of freshness vs. overhead.

Result object fields (selected):

- `Percentiles.p50|p90|p99`
- `QuantileStrategy` (reports `StreamingReservoir` even if legacy alias `StreamingP2` was used)
- `StreamingWindowCount` (current reservoir size; 0 when not streaming yet)

Legacy alias:

- `StreamingP2` is accepted but now maps to `StreamingReservoir` and emits a deprecation warning unless `-Quiet` is specified.

Accuracy guidance:

- For relatively stable latency distributions, `StreamCapacity=300-500` keeps p50/p90 within a few milliseconds (or a few percent relative error) versus exact in typical quick-iteration scenarios.
- Increase capacity or enable reconciliation if p99 drifts (especially with bimodal or bursty latency patterns).
- Hybrid mode is helpful when early, small-sample percentiles must be exact for initial diagnostics, but you still want bounded memory for a long soak run.

Example hybrid run with reconciliation:

```powershell
Import-Module ./module/CompareLoop/CompareLoop.psm1 -Force
$exec = { param($cli,$b,$h,$args) Start-Sleep -Milliseconds (5 + (Get-Random -Max 10)); 0 }
$r = Invoke-IntegrationCompareLoop -Base Base.vi -Head Head.vi -MaxIterations 2000 -IntervalSeconds 0 `
  -CompareExecutor $exec -SkipValidation -PassThroughPaths -BypassCliValidation -Quiet `
  -QuantileStrategy Hybrid -HybridExactThreshold 400 -StreamCapacity 500 -ReconcileEvery 2000
$r.Percentiles
```

If reconciliation is enabled it triggers at the configured cadence only after streaming becomes active (Hybrid post-threshold or StreamingReservoir immediately).

Tuning checklist:

1. Need absolute accuracy and short run? Use `Exact`.
2. Long run, bounded memory? Use `StreamingReservoir` with suitable `StreamCapacity`.
3. Want accurate early baseline then bounded? Use `Hybrid` + set `HybridExactThreshold`.
4. Observing drift over hours? Introduce `-ReconcileEvery` at a multiple of capacity.
5. Tail (p99) noisy? Increase capacity or reconciliation frequency modestly.

Future considerations (open to contributions): true P² marker implementation, advanced tail percentiles beyond those requested (e.g., p99.99), weighted / stratified sampling strategies.


Switches `-SkipValidation` and `-PassThroughPaths` exist solely for unit-style testing; omit them in real usage.

## Advanced loop parameters (module & delegated script)

The enhanced module (`CompareLoop`) exposes additional tuning/automation parameters beyond the basic scaffold:

| Area | Parameters | Purpose |
|------|------------|---------|
| Event-driven triggering | `-UseEventDriven`, `-DebounceMilliseconds` | React to filesystem changes instead of fixed polling. Debounce consolidates bursts. |
| Adaptive backoff | `-AdaptiveInterval`, `-MinIntervalSeconds`, `-MaxIntervalSeconds`, `-BackoffFactor` | Increase interval during quiet periods; reset on activity. |
| Diff summaries | ``-DiffSummaryFormat (Text\|Markdown\|Html)``, `-DiffSummaryPath` | Generate a one-shot human-readable summary after at least one diff. |
| Percentile metrics | (auto) `Percentiles.p50/p90/p99` | Exposed in result object when at least one non-skipped iteration ran. |
| Histogram | (auto) `Histogram[]` | Coarse distribution of iteration durations (5 bins). |
| Re-baseline helper | `-RebaselineAfterCleanCount`, `-ApplyRebaseline` | Detect sustained clean streaks and optionally treat head timestamp as new base reference. |
| Dependency injection | `-CompareExecutor`, `-BypassCliValidation`, `-SkipValidation`, `-PassThroughPaths` | Unit / synthetic testing without real LVCompare. |
| Diff control | `-FailOnDiff` | Early terminate loop when first diff occurs. |

Example combining several advanced features:

```powershell
Invoke-IntegrationCompareLoop `
  -Base 'C:\repos\main\ControlLoop.vi' `
  -Head 'C:\repos\feature\ControlLoop.vi' `
  -UseEventDriven -DebounceMilliseconds 400 `
  -AdaptiveInterval -MinIntervalSeconds 1 -MaxIntervalSeconds 20 -BackoffFactor 1.8 `
  -RebaselineAfterCleanCount 5 `
  -DiffSummaryFormat Markdown -DiffSummaryPath .\diff-summary.md `
  -LvCompareArgs '-nobdcosm -nofppos -noattr' `
  -FailOnDiff
```

Result object excerpt:

```powershell
$r = Invoke-IntegrationCompareLoop -Base ... -Head ... -MaxIterations 3 -UseEventDriven -AdaptiveInterval -SkipIfUnchanged
$r | Select-Object Iterations,DiffCount,ErrorCount,Mode,AverageSeconds,Percentiles,RebaselineApplied | Format-List
```

For full schema details see `docs/COMPARE_LOOP_MODULE.md`.

## What's New (Snapshot v2 & Dynamic Percentiles)

Recent enhancements introduce richer latency telemetry and more flexible percentile analysis:

- metrics-snapshot-v2: Snapshot lines now include `percentiles` (dynamic object), `requestedPercentiles` (echo of your list or defaults), and optional `histogram` when `-IncludeSnapshotHistogram` is used.
- Custom percentile lists: Supply `-CustomPercentiles '50,75,90,97.5,99.9'` (comma/space separated). Values must be >0 and <100; duplicates removed; max 50 entries.
- Fractional percentile labels: Dots become underscores (e.g. 97.5 -> `p97_5`, 99.9 -> `p99_9`).
- Backward compatibility: Legacy `p50/p90/p99` still emitted at top-level in snapshots and result objects for existing consumers.
- Inline snapshot enrichment: Percentiles & histogram computed per-emission without relying on final aggregation logic.

Quick example (custom list + histogram + snapshots every 5 iterations):

```powershell
$exec = { param($cli,$b,$h,$args) Start-Sleep -Milliseconds (5 + (Get-Random -Max 20)); 0 }
Invoke-IntegrationCompareLoop -Base Base.vi -Head Head.vi -MaxIterations 25 -IntervalSeconds 0 -CompareExecutor $exec -SkipValidation -PassThroughPaths -BypassCliValidation -CustomPercentiles '50 75 90 97.5 99.9' -MetricsSnapshotEvery 5 -MetricsSnapshotPath snapshots.ndjson -IncludeSnapshotHistogram -Quiet
Get-Content snapshots.ndjson | Select-Object -First 2
```

Parsing dynamic percentiles (robust to optional keys):

```powershell
$line = Get-Content snapshots.ndjson -First 1 | ConvertFrom-Json
$pKeys = $line.percentiles | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
"Available percentile keys: $($pKeys -join ', ')"
```

See `docs/COMPARE_LOOP_MODULE.md` for full snapshot v2 schema.


Dispatcher JSON outputs & customization

The local dispatcher (`Invoke-PesterTests.ps1`) emits:

- `pester-summary.json` (or custom name via `-JsonSummaryPath`) with aggregate metrics
- `pester-failures.json` only when there are failing tests (array of failed test objects)

`pester-summary.json` schema:

```jsonc
{
  "total": 0,
  "passed": 0,
  "failed": 0,
  "errors": 0,
  "skipped": 0,
  "duration_s": 0.00,
  "timestamp": "2025-01-01T00:00:00.0000000Z",
  "pesterVersion": "5.x.x",
  "includeIntegration": false
}
```

Change the JSON filename (while keeping location) via:

```powershell
./Invoke-PesterTests.ps1 -JsonSummaryPath custom-summary.json
```

Failure diagnostics

When failures occur the dispatcher prints:

1. A table-style list of failing tests (name + duration)
2. Error messages per failed test
3. Writes `pester-failures.json` for downstream tooling

Nightly diagnostics

The workflow `pester-diagnostics-nightly.yml` sets `ENABLE_DIAGNOSTIC_FAIL=1`, triggering a synthetic failing test (skipped otherwise). This validates the failure reporting path without marking the workflow failed (uses `continue-on-error`). Artifacts include both JSON files for inspection.

Dispatcher artifact manifest

The dispatcher emits a `pester-artifacts.json` manifest listing all generated artifacts with their types and schema versions:

| Artifact | Type | Schema Version | Always Present |
|----------|------|----------------|----------------|
| `pester-results.xml` | `nunitXml` | N/A | Yes |
| `pester-summary.txt` | `textSummary` | N/A | Yes |
| `pester-summary.json` | `jsonSummary` | `1.0.0` | Yes |
| `pester-failures.json` | `jsonFailures` | `1.0.0` | Only on failures (or with `-EmitFailuresJsonAlways`) |

Example manifest:

```jsonc
{
  "manifestVersion": "1.0.0",
  "generatedAt": "2025-01-01T00:00:00.0000000Z",
  "artifacts": [
    { "file": "pester-results.xml", "type": "nunitXml" },
    { "file": "pester-summary.txt", "type": "textSummary" },
    { "file": "pester-summary.json", "type": "jsonSummary", "schemaVersion": "1.0.0" },
    { "file": "pester-failures.json", "type": "jsonFailures", "schemaVersion": "1.0.0" }
  ]
}
```

### -EmitFailuresJsonAlways flag

By default, `pester-failures.json` is only created when tests fail. To always emit it (as an empty array `[]` on success), use:

```powershell
./Invoke-PesterTests.ps1 -EmitFailuresJsonAlways
```

**Rationale:** Downstream tools can unconditionally parse `pester-failures.json` without checking for its existence, simplifying CI/CD pipelines that consume failure data.

Schema version policy

All JSON artifacts include schema versions for forward compatibility:

- **`summaryVersion`**: Schema for `pester-summary.json`
- **`failuresVersion`**: Schema for `pester-failures.json`
- **`manifestVersion`**: Schema for `pester-artifacts.json`

Current versions: **1.0.0** for all schemas.

**Versioning rules:**

- **Patch bump** (e.g., 1.0.0 → 1.0.1): Additive fields only; existing parsers unaffected
- **Minor bump** (e.g., 1.0.0 → 1.1.0): Additive monitored fields that tools should start tracking
- **Major bump** (e.g., 1.0.0 → 2.0.0): Breaking changes (field removal, rename, type change)

Consumers should check `schemaVersion` and handle unknown major versions gracefully.

