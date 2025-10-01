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

**-EmitFailuresJsonAlways flag**

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

