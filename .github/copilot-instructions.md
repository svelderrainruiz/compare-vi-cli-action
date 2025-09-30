# Copilot Instructions for this repository# Copilot Instructions for this repository



Important model preferenceImportant model preference

- Use Claude Sonnet 4 for all clients by default for coding, analysis, and refactors. If unavailable, ask for a fallback before proceeding.- Use Claude Sonnet 4 for all clients by default for coding, analysis, and refactors. If unavailable, ask for a fallback before proceeding.



Confirmed architecture and purposeConfirmed architecture and purpose

- This repo is a composite GitHub Action that invokes NI's LabVIEW Compare VI CLI to diff two `.vi` files.- This repo is a composite GitHub Action that invokes NI's LabVIEW Compare VI CLI to diff two `.vi` files.

- Reference: https://www.ni.com/docs/en-US/bundle/labview/page/compare-vi-cli.html- Reference: https://www.ni.com/docs/en-US/bundle/labview/page/compare-vi-cli.html

- Supported LabVIEW: 2025 Q3 on self-hosted Windows runners with LabVIEW installed.- Supported LabVIEW: 2025 Q3 on self-hosted Windows runners with LabVIEW installed.

- Core implementation: Single PowerShell script in `action.yml` runs section with comprehensive error handling and path resolution.- Core implementation: Single PowerShell script in `action.yml` runs section with comprehensive error handling and path resolution.



Developer workflow (PowerShell/pwsh)Developer workflow (PowerShell/pwsh)

- Shell for all steps: PowerShell (`pwsh`) - all commands, paths, and escaping follow Windows PowerShell conventions.- Shell for all steps: PowerShell (`pwsh`) - all commands, paths, and escaping follow Windows PowerShell conventions.

- Use composite action (`using: composite`) to call the CLI, capture exit code, and write outputs via `$GITHUB_OUTPUT`.- Use composite action (`using: composite`) to call the CLI, capture exit code, and write outputs via `$GITHUB_OUTPUT`.

- Built-in policy: `fail-on-diff` defaults to `true` and fails the job if differences are detected.- Built-in policy: `fail-on-diff` defaults to `true` and fails the job if differences are detected.

- Always emit outputs (`diff`, `exitCode`, `cliPath`, `command`) before any failure for workflow branching and diagnostics.- Always emit outputs (`diff`, `exitCode`, `cliPath`, `command`) before any failure for workflow branching and diagnostics.ructions for this repository



Inputs/outputs contractImportant model preference

- Inputs:- Use Claude Sonnet 4 for all clients by default for coding, analysis, and refactors. If unavailable, ask for a fallback before proceeding.

  - `base`: path to the base `.vi`

  - `head`: path to the head `.vi`Confirmed architecture and purpose

  - `lvComparePath` (optional): full path to `LVCompare.exe` if not on `PATH`- This repo is a composite GitHub Action that invokes NI’s LabVIEW Compare VI CLI to diff two `.vi` files.

  - `lvCompareArgs` (optional): extra CLI flags, space-delimited; quotes supported- Reference: https://www.ni.com/docs/en-US/bundle/labview/page/compare-vi-cli.html

  - `working-directory` (optional): process CWD; relative `base`/`head` are resolved from here- Supported LabVIEW: 2025 Q3 on self-hosted Windows runners with LabVIEW installed.

  - `fail-on-diff` (optional, default `true`)

- Environment:Developer workflow (PowerShell/pwsh)

  - `LVCOMPARE_PATH` (optional): resolves the CLI before `PATH` and known install locations- Shell for all steps: PowerShell (`pwsh`).

- Outputs:- Use composite action (`using: composite`) to call the CLI, capture exit code, and write outputs via `$GITHUB_OUTPUT`.

  - `diff`: `true|false` whether differences were detected (0=no diff, 1=diff)- Built-in policy: `fail-on-diff` defaults to `true` and fails the job if differences are detected.

  - `exitCode`: raw exit code from the CLI

  - `cliPath`: resolved path to the executableInputs/outputs contract

  - `command`: exact quoted command line executed- Inputs:

  - `base`: path to the base `.vi`

Composite action implementation notes  - `head`: path to the head `.vi`

- Resolve CLI path priority: `lvComparePath` → `LVCOMPARE_PATH` env → `Get-Command LVCompare.exe` → common 2025 Q3 locations (`C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`, `C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe`). If not found, error with guidance.  - `lvComparePath` (optional): full path to `LVCompare.exe` if not on `PATH`

- Path resolution: Relative `base`/`head` paths are resolved from `working-directory` if set, then converted to absolute paths before CLI invocation.  - `lvCompareArgs` (optional): extra CLI flags, space-delimited; quotes supported

- Arguments parsing: `lvCompareArgs` supports space-delimited tokens with quoted strings (`"path with spaces"`), parsed via regex `"[^"]+"|\S+`.  - `working-directory` (optional): process CWD; relative `base`/`head` are resolved from here

- Command reconstruction: Build quoted command string for auditability using custom `Quote()` function that escapes as needed.  - `fail-on-diff` (optional, default `true`)

- Always set outputs before failing the step so workflows can branch on `diff`.- Environment:

- API principle: expose full LVCompare functionality via `lvCompareArgs`. Do not hardcode opinionated flags.  - `LVCOMPARE_PATH` (optional): resolves the CLI before `PATH` and known install locations

- Step summary: Always write structured markdown summary to `$GITHUB_STEP_SUMMARY` with working directory, resolved paths, CLI path, command, exit code, and diff result.- Outputs:

  - `diff`: `true|false` whether differences were detected (0=no diff, 1=diff)

Example resources  - `exitCode`: raw exit code from the CLI

- Smoke test workflow: `.github/workflows/smoke.yml` (manual dispatch; self-hosted Windows).  - `cliPath`: resolved path to the executable

- Validation workflow: `.github/workflows/validate.yml` (markdownlint + actionlint on PRs).  - `command`: exact quoted command line executed

- Test mock workflow: `.github/workflows/test-mock.yml` (GitHub-hosted runners, mocks CLI).

- Release workflow: `.github/workflows/release.yml` (reads matching section from `CHANGELOG.md` for tag body).Composite action implementation notes

- Runner setup guide: `docs/runner-setup.md`.- Resolve CLI path priority: `lvComparePath` → `LVCOMPARE_PATH` env → `Get-Command LVCompare.exe` → common 2025 Q3 locations (`C:\Program Files\NI\LabVIEW 2025\LVCompare.exe`, `C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe`). If not found, error with guidance.

- Path resolution: Relative `base`/`head` paths are resolved from `working-directory` if set, then converted to absolute paths before CLI invocation.

Testing patterns- Arguments parsing: `lvCompareArgs` supports space-delimited tokens with quoted strings (`"path with spaces"`), parsed via regex `"[^"]+"|\S+`.

- Manual testing via smoke test workflow: dispatch with real `.vi` file paths to validate on self-hosted runner.- Command reconstruction: Build quoted command string for auditability using custom `Quote()` function that escapes as needed.

- Validation uses `ubuntu-latest` for linting (markdownlint, actionlint) - no LabVIEW dependency.- Always set outputs before failing the step so workflows can branch on `diff`.

- Mock testing simulates CLI on GitHub-hosted runners without LabVIEW installation.- API principle: expose full LVCompare functionality via `lvCompareArgs`. Do not hardcode opinionated flags.

- Step summary: Always write structured markdown summary to `$GITHUB_STEP_SUMMARY` with working directory, resolved paths, CLI path, command, exit code, and diff result.

Operational constraints

- Requires LabVIEW on the runner; GitHub-hosted runners do not include it.Example resources

- Use Windows paths and escape backslashes properly in YAML.- Smoke test workflow: `.github/workflows/smoke.yml` (manual dispatch; self-hosted Windows).

- CLI exit code mapping: 0=no diff, 1=diff detected, other=failure with diagnostic outputs.- Validation workflow: `.github/workflows/validate.yml` (markdownlint + actionlint on PRs).

- Test mock workflow: `.github/workflows/test-mock.yml` (GitHub-hosted runners, mocks CLI).

Release workflow- Release workflow: `.github/workflows/release.yml` (reads matching section from `CHANGELOG.md` for tag body).

- Tags follow semantic versioning (e.g., `v0.1.0`).- Runner setup guide: `docs/runner-setup.md`.

- Release workflow extracts changelog section matching tag name from `CHANGELOG.md`.

- Keep changelog format: `## [vX.Y.Z] - YYYY-MM-DD` for automated extraction.Testing patterns

- Manual testing via smoke test workflow: dispatch with real `.vi` file paths to validate on self-hosted runner.

Next steps for contributors- Validation uses `ubuntu-latest` for linting (markdownlint, actionlint) - no LabVIEW dependency.

- Tag a release (e.g., `v0.1.0`) and keep README usage in sync.- Mock testing simulates CLI on GitHub-hosted runners without LabVIEW installation.

- Evolve `README.md` with commonly used LVCompare flag patterns while keeping full pass-through.
Operational constraints
- Requires LabVIEW on the runner; GitHub-hosted runners do not include it.
- Use Windows paths and escape backslashes properly in YAML.
- CLI exit code mapping: 0=no diff, 1=diff detected, other=failure with diagnostic outputs.

Release workflow
- Tags follow semantic versioning (e.g., `v0.1.0`).
- Release workflow extracts changelog section matching tag name from `CHANGELOG.md`.
- Keep changelog format: `## [vX.Y.Z] - YYYY-MM-DD` for automated extraction.

Next steps for contributors
- Tag a release (e.g., `v0.1.0`) and keep README usage in sync.
- Evolve `README.md` with commonly used LVCompare flag patterns while keeping full pass-through.
