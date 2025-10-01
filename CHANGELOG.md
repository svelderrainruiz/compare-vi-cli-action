# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]
 
### Added (Features)

- Enhanced dispatcher failure diagnostics: enumerates failed tests with names, durations, and messages; summarizes skipped tests.
- Machine-readable JSON summary artifact (`pester-summary.json`) emitted alongside existing text and XML results.
- Synthetic diagnostic test file (`Invoke-PesterTests.Diagnostics.Tests.ps1`) to allow opt-in observation of failure diagnostics (activate by setting `ENABLE_DIAGNOSTIC_FAIL` env var).
- `-JsonSummaryPath` parameter to dispatcher allowing custom JSON summary filename.
- Emission of `pester-failures.json` on test failure with structured failed test data.
- Nightly diagnostics workflow (`pester-diagnostics-nightly.yml`) exercising enhanced failure path without failing build.
- Job summary metric block in self-hosted Pester workflow using JSON summary.

### Fixed

- Restored backward-compatible IncludeIntegration string comparison branch so legacy pattern-based test continues to pass.

### Notes

- JSON summary schema: `{ total, passed, failed, errors, skipped, duration_s, timestamp, pesterVersion, includeIntegration }`.
- Failure diagnostics only appear when there are actual failures; normal passing runs remain concise.


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
