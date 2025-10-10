<!-- markdownlint-disable-next-line MD041 -->
# Runner Setup (Self-Hosted Windows)

Quick checklist for provisioning a self-hosted runner compatible with the LVCompare action.

## Requirements

- Windows 10/11 or Server (64-bit).
- LabVIEW 2025 Q3 with LVCompare CLI feature.
- PowerShell 7 (`pwsh`).
- Git installed.

## Steps

1. Install GitHub Actions runner.
2. Configure labels: `self-hosted`, `Windows`, `X64`.
3. Install LabVIEW + LVCompare at canonical path.
4. Add environment variables (system-wide or runner service):
   - `LV_BASE_VI`, `LV_HEAD_VI` (sample fixtures).
   - `LV_NO_ACTIVATE=1`, `LV_SUPPRESS_UI=1`, `LV_CURSOR_RESTORE=1`.
5. Install Node.js (optional, for repo scripts/watchers).
6. Start runner service and confirm idle status.

## Validation

```powershell
Test-Path 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
[Environment]::GetEnvironmentVariable('LV_BASE_VI', 'Machine')
```

Run `Pester (self-hosted, real CLI)` workflow manually to confirm integration tests pass.

## References

- [`docs/SELFHOSTED_CI_SETUP.md`](./SELFHOSTED_CI_SETUP.md)
- [`docs/E2E_TESTING_GUIDE.md`](./E2E_TESTING_GUIDE.md)
