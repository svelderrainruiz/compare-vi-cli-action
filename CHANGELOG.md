# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

- (No changes yet)

## [v0.2.0] - 2025-10-01

### Added

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
