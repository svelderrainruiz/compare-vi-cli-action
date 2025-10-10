<!-- markdownlint-disable-next-line MD041 -->
# Self-Hosted CI Setup

Minimal steps to provision a Windows runner suitable for LVCompare workflows.

## Installations

1. GitHub Actions runner (service mode).
2. LabVIEW 2025 Q3 with LVCompare CLI feature.
3. PowerShell 7 (`pwsh`).
4. Git + Node.js (optional for local tooling).

## Runner configuration

- Labels: `self-hosted`, `Windows`, `X64`.
- Service account requires access to VI fixtures and temporary directories.
- Environment variables (system scope recommended):
  - `LV_BASE_VI`, `LV_HEAD_VI` (sample VIs).
  - `LV_NO_ACTIVATE=1`, `LV_SUPPRESS_UI=1`, `LV_CURSOR_RESTORE=1`.
  - `WATCH_RESULTS_DIR` (optional) for watcher output.
- Secrets/variables:
  - Repo secret `XCLI_PAT` (scopes: `repo`, `actions:write`) for command dispatch feedback.

## Verification

```powershell
Test-Path 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
[Environment]::GetEnvironmentVariable('LV_BASE_VI', 'Machine')
[Environment]::GetEnvironmentVariable('LV_HEAD_VI', 'Machine')
```

Dispatch `Pester (self-hosted, real CLI)` manually to confirm environment validation and tests pass.

## Maintenance

- Keep LabVIEW and Windows patched.
- Monitor runner health (Actions → Runners).
- Rotate PATs and verify secrets annually.
- Periodically refresh fixture VIs and environment variables.

Further reading: [`docs/E2E_TESTING_GUIDE.md`](./E2E_TESTING_GUIDE.md), [`docs/ENVIRONMENT.md`](./ENVIRONMENT.md).
