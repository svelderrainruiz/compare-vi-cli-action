<!-- markdownlint-disable-next-line MD041 -->
# End-to-End Testing (Self-Hosted Windows)

Quick checklist for validating the LVCompare composite action on a self-hosted runner.

## Prerequisites

- Runner labels: `self-hosted`, `Windows`, `X64` (Settings → Actions → Runners).
- LabVIEW 2025 Q3 installed with LVCompare at
  `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`.
- PowerShell 7 (`pwsh`).
- Repository variables/secrets:
  - `LV_BASE_VI`, `LV_HEAD_VI` – sample VIs (distinct).
  - `XCLI_PAT` – PAT with `repo`, `actions:write`.

## Pre-flight checks

```powershell
Test-Path 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
[Environment]::GetEnvironmentVariable('LV_BASE_VI', 'Machine')
[Environment]::GetEnvironmentVariable('LV_HEAD_VI', 'Machine')
```

Verify the runner is online (Settings → Actions → Runners) before dispatching workflows.

## Core scenarios

1. **Integration workflow (self-hosted real CLI)**
   - Run `Pester (self-hosted, real CLI)` manually (`include_integration=true`).
   - Expect environment validation summary, Pester install step, and `Tests Passed` output.
2. **Smoke workflow**
   - Trigger via PR label `smoke` or manual dispatch.
   - Validate quick LVCompare run completes and artifacts upload.
3. **Command dispatcher**
   - Use comment `/run pester-selfhosted` on PR.
   - Confirm workflow URL posted back to PR, run obeys provenance summary order.
4. **Orchestrated single vs matrix**
   - `pwsh -File tools/Dispatch-WithSample.ps1 ... -Strategy single`.
   - Repeat with `-Strategy matrix`.
   - Compare `tests/results/provenance.json` artifacts; differences limited to identifiers and strategy.

## What to verify

- Guard/telemetry crumbs exist (`tests/results/_diagnostics`, `_wire`, `_agent`).
- Comparison artifacts uploaded (`compare-exec.json`, HTML diff if enabled).
- Job summary includes Run Provenance, Invoker snapshots, Compare outcome, rerun hint.
- Environment validation fails gracefully when CLI or env vars missing.

## Troubleshooting quick hits

| Issue | Action |
| ----- | ------ |
| Run stuck in queued | Check runner status/labels, restart runner service |
| CLI not found | Reinstall or restore LVCompare to canonical path |
| VIs missing | Fix `LV_BASE_VI` / `LV_HEAD_VI` paths or permissions |
| PR comments ignored | Verify `XCLI_PAT` secret and commenter association |

## Follow-up

- Capture screenshots/notes for successful workflows.
- Share results with the team and update docs if deviations observed.
- Monitor runner health (weekly) and refresh VI fixtures periodically.

Need deeper context? See:

- [`docs/SELFHOSTED_CI_SETUP.md`](./SELFHOSTED_CI_SETUP.md) – detailed runner setup.
- [`docs/TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)
- [`docs/DEV_DASHBOARD_PLAN.md`](./DEV_DASHBOARD_PLAN.md)
