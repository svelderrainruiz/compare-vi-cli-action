<!-- markdownlint-disable-next-line MD041 -->
# Quantile Accuracy Notes

Loop-mode quantile estimation strategies employed by the LVCompare loop harness.

## Strategies

| Strategy | Description |
| -------- | ----------- |
| `Exact` | Stores every sample (memory intensive, precise) |
| `StreamingReservoir` | Reservoir sampling with configurable capacity |
| `Hybrid` | Uses Exact for initial window, then switches to streaming |

## Key tweaks

- `stream-capacity` / `LOOP_STREAM_CAPACITY` – reservoir size.
- `reconcile-every` – rebuild reservoir periodically.
- `hybrid-exact-threshold` – number of iterations before hybrid switch.

## Guidance

- Use `Exact` for short-lived loops where memory is not a concern.
- Prefer `StreamingReservoir` for long runs; adjust capacity to balance accuracy vs memory.
- `Hybrid` gives precise early measurements while capping memory later.

See [`docs/COMPARE_LOOP_MODULE.md`](./COMPARE_LOOP_MODULE.md) for loop configuration details.
