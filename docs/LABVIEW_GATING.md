<!-- markdownlint-disable-next-line MD041 -->
# LabVIEW Gating Reference

Scripts and knobs used to verify LabVIEW/LVCompare state on self-hosted runners.

## Guard helpers

| Script | Purpose |
| ------ | ------- |
| `tools/Ensure-LabVIEWClosed.ps1` | Stops LabVIEW before/after runs (respects cleanup env vars) |
| `tools/Close-LVCompare.ps1` | Graceful shutdown or forced kill with timeout |
| `tools/Detect-RogueLV.ps1` | Reports rogue LabVIEW/LVCompare processes (`-FailOnRogue` to fail) |

## Recommended environment defaults

| Variable | Default |
| -------- | ------- |
| `CLEAN_LV_BEFORE`, `CLEAN_LV_AFTER`, `CLEAN_LV_INCLUDE_COMPARE` | `true` |
| `LV_NO_ACTIVATE`, `LV_SUPPRESS_UI`, `LV_CURSOR_RESTORE` | `1` |
| `LV_IDLE_WAIT_SECONDS`, `LV_IDLE_MAX_WAIT_SECONDS` | `2`, `5` |

Set these in runner environment or workflow `env` blocks to minimize UI prompts.

## Usage example

```powershell
$env:LV_SUPPRESS_UI = '1'
$env:LV_NO_ACTIVATE = '1'
$env:LV_CURSOR_RESTORE = '1'
pwsh -File tools/Ensure-LabVIEWClosed.ps1
pwsh -File scripts/CompareVI.ps1 -Base VI1.vi -Head VI2.vi
```

## Troubleshooting

- Use `tools/Detect-RogueLV.ps1 -AppendToStepSummary` in workflows for visibility.
- Combine with session locks (`SESSION_LOCK_ENABLED=1`) to avoid concurrent CLI runners.

## Related docs

- [`docs/ENVIRONMENT.md`](./ENVIRONMENT.md)
- [`docs/TROUBLESHOOTING.md`](./TROUBLESHOOTING.md)
