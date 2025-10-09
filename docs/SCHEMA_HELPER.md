<!-- markdownlint-disable-next-line MD041 -->
# Schema Helper

Utilities for validating JSON/NDJSON artefacts produced by the dispatcher and loop modules.

## Scripts

| Script | Purpose |
| ------ | ------- |
| `tools/Invoke-JsonSchemaLite.ps1` | Validate JSON against schema-lite definitions |
| `tools/Schema-Lint.ps1` | Batch validation helper (optional) |

## Common schemas

| Artefact | Schema |
| -------- | ------ |
| Run summary (`tests/results/pester-summary.json`) | `docs/schemas/pester-summary-v1_5.schema.json` |
| Loop events NDJSON | `docs/schemas/loop-event-v1.schema.json` |
| Leak report | `docs/schemas/pester-leak-report-v1.schema.json` |
| Dispatcher guard crumb | `docs/schemas/dispatcher-results-guard-v1.schema.json` |

## Usage

```powershell
pwsh -File tools/Invoke-JsonSchemaLite.ps1 `
  -JsonPath tests/results/pester-summary.json `
  -SchemaPath docs/schemas/pester-summary-v1_5.schema.json
```

Combine with `Get-ChildItem` / `ForEach-Object` to validate batches of artefacts in CI or
local runs.

## Tips

- Schema-lite tolerates unknown fields; it checks presence, type, and allowed values.
- Use schema checks when evolving summary formats to avoid regressions.
- Integrate into workflows after generating summaries to catch malformed output early.
