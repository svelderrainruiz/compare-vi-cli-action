# Copilot Instructions for this repository

Important model preference
- Use Claude Sonnet 4 for all clients by default for coding, analysis, and refactors. If unavailable, ask for a fallback before proceeding.

Confirmed architecture and purpose
- This repo is a composite GitHub Action that invokes NI’s LabVIEW Compare VI CLI to diff two `.vi` files.
- Reference: https://www.ni.com/docs/en-US/bundle/labview/page/compare-vi-cli.html
- Supported LabVIEW: 2025 Q3 on self-hosted Windows runners with LabVIEW installed.

Developer workflow (PowerShell/pwsh)
- Shell for all steps: PowerShell (`pwsh`).
- Use composite action (`using: composite`) to call the CLI, capture exit code, and write outputs via `$GITHUB_OUTPUT`.
- Built-in policy: `fail-on-diff` defaults to `true` and fails the job if differences are detected.

Inputs/outputs contract
- Inputs:
  - `base`: path to the base `.vi`
  - `head`: path to the head `.vi`
  - `lvComparePath` (optional): full path to `LVCompare.exe` if not on `PATH`
  - `lvCompareArgs` (optional): extra CLI flags, space-delimited; quotes supported
  - `working-directory` (optional): process CWD; relative `base`/`head` are resolved from here
  - `fail-on-diff` (optional, default `true`)
- Environment:
  - `LVCOMPARE_PATH` (optional): resolves the CLI before `PATH` and known install locations
- Outputs:
  - `diff`: `true|false` whether differences were detected (0=no diff, 1=diff)
  - `exitCode`: raw exit code from the CLI
  - `cliPath`: resolved path to the executable
  - `command`: exact quoted command line executed

Composite action implementation notes
- Resolve CLI path priority: `lvComparePath` → `LVCOMPARE_PATH` env → `Get-Command LVCompare.exe` → common 2025 Q3 locations (`C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`, `C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe`). If not found, error with guidance.
- Always set outputs before failing the step so workflows can branch on `diff`.
- API principle: expose full LVCompare functionality via `lvCompareArgs`. Do not hardcode opinionated flags.

Example resources
- Smoke test workflow: `.github/workflows/smoke.yml` (manual dispatch; self-hosted Windows).
- Validation workflow: `.github/workflows/validate.yml` (markdownlint + actionlint on PRs).
- Release workflow: `.github/workflows/release.yml` (reads matching section from `CHANGELOG.md` for tag body).
- Runner setup guide: `docs/runner-setup.md`.

Operational constraints
- Requires LabVIEW on the runner; GitHub-hosted runners do not include it.
- Use Windows paths and escape backslashes properly in YAML.

Next steps for contributors
- Tag a release (e.g., `v0.1.0`) and keep README usage in sync.
- Evolve `README.md` with commonly used LVCompare flag patterns while keeping full pass-through.
