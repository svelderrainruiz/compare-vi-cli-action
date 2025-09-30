# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

- TBD

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
