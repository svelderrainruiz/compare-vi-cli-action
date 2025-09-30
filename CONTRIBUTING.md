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
- Exit code mapping: 0 = no diff, 1 = diff; any other exit code should fail fast (outputs preserved)
- Full CLI flags are passed through `lvCompareArgs` (quotes supported)
- You can set `working-directory` to control relative path resolution for `base` and `head`

Style and validation

- PRs run markdownlint and actionlint via `.github/workflows/validate.yml`
- Run `.github/workflows/test-mock.yml` on PRs (windows-latest); use smoke on self-hosted for real LVCompare
- Keep README examples accurate and executable

Branch protection (maintainers)

1) In repository settings → Branches → Add rule for `main`
2) Require status checks to pass before merging:
   - `Validate`
   - `Test (mock)`
3) Optionally require linear history and dismiss stale approvals

Repository topics (maintainers)

- Add topics for discoverability: `labview`, `lvcompare`, `vi`, `composite-action`, `windows`, `github-actions`

Marketplace listing (maintainers)

- Ensure `action.yml` `name`, `description`, and `branding` are correct (icon: `git-merge`, color: `blue`)
- Publish the repository to GitHub Marketplace
- Update `README.md` with a Marketplace link after publication

Releases

- Tag semantic versions (e.g., `v0.1.0`); the release workflow reads `CHANGELOG.md` to generate release notes
- After tagging, ensure README examples reference the latest stable tag

Maintainers

- CODEOWNERS: `@svelderrainruiz`
