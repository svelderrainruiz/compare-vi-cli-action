# Contributing

Thank you for contributing to `compare-vi-cli-action`!

Prerequisites

- Self-hosted Windows runner with LabVIEW 2025 Q3 installed and licensed
- Ability to provide LVCompare path via PATH, `LVCOMPARE_PATH`, or `lvComparePath`

Getting started

- Fork and clone the repo
- Create a feature branch
- Use the smoke test workflow (`.github/workflows/smoke.yml`) to validate changes against sample `.vi` files on your self-hosted runner

Action development tips

- The action is composite with `pwsh` steps; prefer small changes and test incrementally
- Exit code mapping: 0 = no diff, 1 = diff; any other exit code should fail fast
- Full CLI flags are passed through `lvCompareArgs` (quotes supported)
- You can set `working-directory` to control relative path resolution for `base` and `head`

Style and validation

- PRs run markdownlint and actionlint via `.github/workflows/validate.yml`
- Keep README examples accurate and executable

Releases

- Tag semantic versions (e.g., `v0.1.0`); the release workflow creates a GitHub Release automatically
- After tagging, update README examples to reference the new tag if needed

Maintainers

- CODEOWNERS: `@svelderrainruiz`
