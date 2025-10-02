# JSON Schema Helper for Tests

This document describes the lightweight JSON shape validation utilities introduced for the test suite:
`tests/TestHelpers.Schema.ps1`.

## Purpose

Many scripts in this repository emit JSON or NDJSON artifacts (run summaries, metrics snapshots, loop
log events, final status objects). The helper provides **structural validation** without introducing
external dependencies or a heavy JSON Schema engine. It focuses on:

- Fast, dependency‑free assertions
- Forward compatibility (extra properties are tolerated)
- Readable failure messages consolidated per file
- Reusable predicates expressed as PowerShell scriptblocks

## Provided Functions

### Assert-JsonShape

```powershell
Assert-JsonShape -Path <jsonFile> -Spec <SpecName> [-Strict]
```

Validates a single JSON document against a named spec. Throws with aggregated failures (missing
required properties, predicate failures). Returns `$true` on success so it can be piped into Pester's
`Should -BeTrue` if desired.

Strict mode: add `-Strict` to also fail on any unexpected (extra) top-level property not declared in
`Required`, `Optional`, or `Types`. This is useful for regression-style “producer must not add new
fields” tests. Keep normal mode for forward-compatible validation.

### Assert-NdjsonShapes

```powershell
Assert-NdjsonShapes -Path <ndjsonFile> -Spec <SpecName> [-Strict]
```

Validates every non-empty line in a newline‑delimited JSON file (NDJSON). Each line is parsed, then
re-serialized and passed through the same internal shape validator used by `Assert-JsonShape`.
Stops on the first invalid line with a descriptive error (line number + predicate issues). Supports
`-Strict` to reject unknown properties per line.

### Export-JsonShapeSchemas

```powershell
Export-JsonShapeSchemas -OutputDirectory schemas/ [-Overwrite]
```

Generates a minimal JSON Schema (Draft 2020-12 style) per spec (`<Spec>.schema.json`) with:

- `required` array from the spec
- all known properties under `properties` (Required + Optional)
- `additionalProperties: false` mirroring Strict expectations


Type predicates are not translated into formal JSON Schema types (kept loose by design); consumers
can extend the generated schemas manually if needed.

## Available Specs

The helper maintains a script-scoped dictionary `$script:JsonShapeSpecs` mapping spec names to
objects with three keys:

- `Required` (string array)
- `Optional` (string array)
- `Types` (hashtable mapping property name -> predicate scriptblock)

Current specs:

| Spec Name    | Description | Emitted By |
|--------------|-------------|------------|
| FinalStatus  | Final loop status JSON (`loop-final-status-v1`) written by `Run-AutonomousIntegrationLoop.ps1` | Final status file via `-FinalStatusJsonPath` |
| RunSummary   | Compare loop run summary (`compare-loop-run-summary-v1`) | `Invoke-IntegrationCompareLoop -RunSummaryJsonPath` |
| SnapshotV2   | Metrics snapshot NDJSON lines (`metrics-snapshot-v2`) | `Invoke-IntegrationCompareLoop -MetricsSnapshotEvery/-MetricsSnapshotPath` |
| LoopEvent    | Loop event & meta NDJSON lines (`loop-script-events-v1`) | `Run-AutonomousIntegrationLoop.ps1` JSON log |

### Predicate Philosophy

Predicates intentionally allow multiple primitive numeric types (`[int]`, `[long]`, `[double]`) and,
for some counters, numeric strings (`"15"`) to make tests tolerant of producer evolution (e.g.
serialization changes or future pipeline stages). Histogram predicates accept arrays, objects, or
strings to avoid flakiness when a producer elects to omit or placeholder a histogram for trivial
runs.

### Adding a New Spec

1. Open `tests/TestHelpers.Schema.ps1`.
2. Insert a new entry:

   ```powershell
   $script:JsonShapeSpecs['MySpec'] = [pscustomobject]@{
     Required = @('schema','id')
     Optional = @('details')
     Types    = @{
       schema  = { param($v) $v -eq 'my-schema-v1' }
       id      = { param($v) $v -is [string] -and $v }
       details = { param($v) -not $v -or $v -is [pscustomobject] }
     }
   }
   ```

3. Use in tests:

   ```powershell
   . "$PSScriptRoot/TestHelpers.Schema.ps1"
   Assert-JsonShape -Path $path -Spec 'MySpec' | Should -BeTrue
   ```

4. If NDJSON, switch to `Assert-NdjsonShapes`.

### Evolving an Existing Spec

- Prefer additive changes (add Optional property + predicate) first.
- When removing or renaming required properties, increment the schema name (e.g., `*-v2`) and add a
  parallel spec instead of mutating the existing one. Update tests gradually.

## Failure Output Examples

```text
Assert-JsonShape FAILED for spec 'RunSummary' on file '.../run-summary.json':
 - missing required property 'schema'
 - property 'iterations' failed type predicate (value='-1')
```

```text
Line 12 invalid JSON in metrics.ndjson: Unexpected end of content
```

## Usage Patterns in Tests

Refactoring existing assertions:

  ```powershell
  # Old:
  ($json.iterations) | Should -Be 15
  # New schema validation + targeted assertion for a key business rule:
  Assert-JsonShape -Path $summaryPath -Spec 'RunSummary' | Should -BeTrue
  ($summary.percentiles.p90) | Should -BeGreaterThan 0
  ```

NDJSON rotation validation:

  ```powershell
  foreach ($file in $segments) {
    Assert-NdjsonShapes -Path $file -Spec 'LoopEvent' | Should -BeTrue
  }
  ```

## When Not to Use

- For deep semantic validation (e.g., verifying percentile ordering) keep specialized assertions.
- For enormous JSON objects where only a few fields matter; schema validation may add overhead.
- For strict JSON Schema compliance (draft spec features) — this helper is intentionally simpler.

## Extending Predicates Safely

Keep predicates small and side-effect free. Avoid throwing inside predicates; instead return `$false`.
If a predicate needs richer diagnostics, enhance the thrown aggregated message in `Assert-JsonShape`
rather than embedding writes in each predicate.

## Internal Design Overview

1. Test calls `Assert-JsonShape` or `Assert-NdjsonShapes`.
2. File read; JSON object(s) parsed with `ConvertFrom-Json`.
3. For each required property: presence check.
4. For each property present with a predicate: execute predicate scriptblock.
5. Collect all failures; if any, throw one aggregated error.
6. Return `$true` on success (makes it pipeline-friendly for Pester `Should`).

`Assert-NdjsonShapes` reuses the same object-level validator by serializing each parsed line to a
scratch temp file to keep logic consolidated (small performance trade-off, large code reuse win).

## Rationale for Flexible Histogram Predicate

 Some runs (especially very short ones) may produce either:

- No histogram (null / omitted)
- Placeholder whitespace
- Fully populated array/object bins

Allowing all keeps tests green during early development; once producer output stabilizes we can
narrow the predicate (document any tightening in CHANGELOG along with spec adjustments).

## Best Practices Checklist

- [ ] Add spec before writing test using it.
- [ ] Keep spec naming consistent with emitted `schema` field (or future `schemaVersion`).
- [ ] Allow optional numeric strings only if producer ambiguity exists.
- [ ] Fail fast but aggregate multiple missing/predicate issues in one assertion.
- [ ] Consider versioning (v1/v2) for breaking field changes—don’t silently mutate existing spec.

## Future Enhancements (Potential)

- Introduce a tiny caching layer for predicate delegates if perf becomes an issue.
- Provide helper to diff two JSON documents against the same spec (schema regression guard).
- Emit machine-readable failure JSON (could integrate into CI artifacts).
- Optional predicate-to-JSON-Schema type inference (best effort) for richer export.

## See Also

- `Invoke-PesterTests.ps1` dispatcher output parsing
- `Run-AutonomousIntegrationLoop.LogRotation.Tests.ps1` (LoopEvent + rotation example)
- `CompareLoop.SnapshotEnrichment.Tests.ps1` (SnapshotV2 NDJSON example)
- `CompareLoop.RunSummary.Tests.ps1` (RunSummary example)

---
Questions or adjustments? Open an issue with the failing JSON sample and the spec name.
