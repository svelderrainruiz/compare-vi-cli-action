# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]
 
_No changes yet._

## [v0.3.0] - 2025-10-01

### Added

- Streaming latency percentile strategy `StreamingReservoir` (bounded ring buffer) for low-memory approximate p50/p90/p99.
- Hybrid quantile strategy (`Hybrid`) that seeds with exact samples then transitions to streaming after `-HybridExactThreshold`.
- Periodic reconciliation option (`-ReconcileEvery`) to rebuild reservoir from all collected durations (uniform stride subsample) reducing long-run drift.
- Configurable reservoir capacity via `-StreamCapacity` (min 10) and exposure of `StreamingWindowCount` in result object for visibility.
- Reconciliation & streaming accuracy tests: `CompareLoop.StreamingQuantiles.Tests.ps1`, `CompareLoop.StreamingReconcile.Tests.ps1`.
- README documentation: comprehensive Streaming Quantile Strategies section (usage, tuning, accuracy guidance, future considerations).
- Dispatcher zero-test safeguard: early exit generates placeholder `pester-results.xml`, `pester-summary.txt`, JSON summary, and artifact manifest when no tests are found.
- Artifact manifest (`pester-artifacts.json`) with schema version identifiers (`summaryVersion`, `failuresVersion`, `manifestVersion`).
- `-EmitFailuresJsonAlways` switch to force emission of empty failures JSON for consistent CI parsing.
- Machine-readable JSON summary artifact (`pester-summary.json`) plus `-JsonSummaryPath` customization parameter.
- Structured failures artifact `pester-failures.json` on failing test runs.
- Synthetic diagnostic test file (`Invoke-PesterTests.Diagnostics.Tests.ps1`) gated by `ENABLE_DIAGNOSTIC_FAIL` env var.
- Nightly diagnostics workflow (`pester-diagnostics-nightly.yml`) exercising enhanced failure path without failing build.
- Job summary metrics block (self-hosted workflow) using JSON summary; integration tests covering manifest and schema validation.

### Changed

- Renamed streaming strategy from `StreamingP2` to `StreamingReservoir`; legacy name retained as deprecated alias with warning.
- Percentile emission logic now branches on Exact / Streaming / Hybrid modes without retaining full sample array for streaming cases.

### Fixed

- Dispatcher: robust handling of zero-test scenario (prevents null path/placeholder failures observed previously).
- Restored backward-compatible `IncludeIntegration` string normalization for legacy pattern-based tests.
- Single-test file array handling (`$testFiles.Count` reliability) and artifact manifest scoping.
- Corrected test assertion operators (`-BeLessOrEqual`) preventing ParameterBindingException during streaming tests.

### Removed

- Legacy experimental P² estimator implementation (fully supplanted by reservoir approach; alias maintained for user continuity).

### Notes

- JSON summary schema: `{ total, passed, failed, errors, skipped, duration_s, timestamp, pesterVersion, includeIntegration, schemaVersion }`.
- Reservoir percentiles use linear interpolation—raise `-StreamCapacity` or enable `-ReconcileEvery` for more stable high-percentile (p99) estimates under bursty distributions.
- Schema version policy: patch for strictly additive fields; minor for additive but monitored fields; major for breaking structural changes.


## [v0.2.0] - 2025-10-01

### Added (Initial Release)

- Output: `compareDurationSeconds` (execution duration in seconds; replaces legacy `durationSeconds` name not present in v0.1.0 release)
- Output: `compareDurationNanoseconds` (high-resolution duration in nanoseconds)
- Output: `compareSummaryPath` (path to generated JSON comparison metadata)
- High-resolution timing instrumentation in `CompareVI.ps1`
- Artifact publishing workflow: `.github/workflows/compare-artifacts.yml` (uploads JSON summary + HTML report, appends timing to job summary)
- Integration label workflow enhancement: timing block now includes seconds, nanoseconds, and combined seconds + ms line
- JSON summary parsing in PR comment workflow (preferred over regex parsing of text summary)

### Changed

- Renamed timing output `durationSeconds` to `compareDurationSeconds`
- PR integration workflow now prefers JSON-derived timing metrics before falling back to textual summary parsing

### Documentation

- README: expanded timing metrics section (nanoseconds + combined line) and documented artifact publishing workflow
- Added guidance on interpreting timing outputs in PR comments and job summaries

### Tests / Internal

- Extended Pester tests to assert presence of `CompareDurationNanoseconds` and related output lines

## [v0.1.0] - 2025-09-30

### Added

- Composite GitHub Action to run NI LVCompare (LabVIEW 2025 Q3) on two .vi files
- Inputs: `base`, `head`, `lvComparePath`, `lvCompareArgs` (quoted args supported), `working-directory`, `fail-on-diff`
- Environment support: `LVCOMPARE_PATH` for CLI discovery
- Outputs: `diff`, `exitCode`, `cliPath`, `command`
- Smoke-test workflow (`.github/workflows/smoke.yml`)
- Validation workflow with markdownlint and actionlint
- Release workflow that creates a GitHub Release on tag push
- Documentation: README, Copilot instructions, runner setup guide, CONTRIBUTING
