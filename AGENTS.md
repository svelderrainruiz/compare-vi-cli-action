# Repository Guidelines

## Project Structure & Module Organization
- `scripts/` orchestration and helper scripts (drift, capture, dispatcher glue).
- `tools/` developer utilities (validate/update manifest, diff helpers, link checks).
- `tests/` Pester suites (`*.Tests.ps1`) tagged `Unit`/`Integration`.
- `module/` reusable PowerShell modules (e.g., compare loops).
- `docs/` guides and JSON schemas; `README.md` is the entry point.
- Canonical fixtures live at repo root (`VI1.vi`, `VI2.vi`) with `fixtures.manifest.json`.

## Build, Test, and Development Commands
- Run unit tests: `./Invoke-PesterTests.ps1`
- Include integration: `./Invoke-PesterTests.ps1 -IncludeIntegration true`
- Quick smoke: `./tools/Quick-DispatcherSmoke.ps1`
- Validate fixtures: `pwsh -File tools/Validate-Fixtures.ps1 -Json`
- Update manifest: `pwsh -File tools/Update-FixtureManifest.ps1 -Allow`

## Coding Style & Naming Conventions
- PowerShell 7+; Pester 5+. Indent with 2 spaces; UTF-8.
- Functions use PascalCase verbs (PowerShell-approved verbs). Locals are camelCase.
- Filenames: tests as `Name.Tests.ps1`; helper modules as `Name.Functions.psm1`.
- Prefer small, composable functions; no global state. Avoid writing outside `tests/results`.

## Testing Guidelines
- Framework: Pester v5. Tag slow/external as `Integration`.
- Test names are behavior-focused: `Describe/Context/It`.
- LVCompare path: `C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe`.
- Integration requires `LV_BASE_VI` and `LV_HEAD_VI` set. No LabVIEW.exe orchestration.

## Commit & Pull Request Guidelines
- Commits: imperative mood, scoped (e.g., "validator: enforce bytes field").
- PRs must include: summary, risks, validation steps, and linked issues.
- Do not start tests if `LabVIEW.exe` is running; close it first. Prefer leaving `LVCompare.exe` alone unless explicitly opted in.
- Attach artifacts from `tests/results/` when relevant (summary/results XML/HTML).

## Security & Configuration Tips
- LVCompare-only interface; do not launch `LabVIEW.exe` from tools.
- Manifest uses strict `bytes` and `sha256`; run validator before pushing.
- Optional leak/cleanup flags: `DETECT_LEAKS=1`, `CLEAN_AFTER=1`, `CLEAN_LVCOMPARE=1`.

## Agent-Specific Notes
- Use `Invoke-PesterTests.ps1` locally and in CI. The dispatcher hard-gates on running `LabVIEW.exe` to keep runs stable. For docs hygiene, run `tools/Check-DocsLinks.ps1` before PRs.
