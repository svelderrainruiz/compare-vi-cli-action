<!-- markdownlint-disable-next-line MD041 -->
# Action Inputs and Outputs

Generated via `npm run generate:outputs`. Summary of the composite action surface.

## Inputs

| Name | Default | Notes |
| ---- | ------- | ----- |
| `base` | — | Path to base `.vi` (required) |
| `head` | — | Path to head `.vi` (required) |
| `fail-on-diff` | `true` | Fail job when a diff is detected |
| `lvCompareArgs` | — | Additional LVCompare CLI flags |
| `lvComparePath` | — | Override LVCompare.exe path |
| `working-directory` | — | Process CWD for relative paths |
| `loop-enabled` | `false` | Enable loop mode metrics |
| `loop-max-iterations` | `1` | Iteration count (`0` = until diff if allowed) |
| `loop-interval-seconds` | `0` | Delay between iterations |
| `loop-simulate` | `true` | Use simulated executor (CI fallback) |
| `loop-simulate-exit-code` | `1` | Exit code returned by simulator |
| `quantile-strategy` | `StreamingReservoir` | Quantile method (Exact / Streaming / Hybrid) |
| `stream-capacity` | `500` | Reservoir capacity |
| `reconcile-every` | `0` | Reservoir rebuild cadence |
| `histogram-bins` | `0` | Histogram buckets (`0` = disabled) |
| `hybrid-exact-threshold` | `200` | Hybrid switch threshold |

## Outputs

- `diff`, `exitCode`, `command`, `cliPath`
- `compareDurationSeconds`, `compareDurationNanoseconds`
- Loop metrics: `iterations`, `diffCount`, `errorCount`, `totalSeconds`, `averageSeconds`
- Quantiles: `p50`, `p90`, `p99`, `quantileStrategy`, `streamingWindowCount`
- Artefact paths: `compareSummaryPath`, `loopResultPath`, `histogramPath`
- `shortCircuitedIdentical` flag when base/head resolve to the same path
