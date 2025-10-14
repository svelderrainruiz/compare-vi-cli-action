<!-- markdownlint-disable-next-line MD041 -->
# Dispatcher Failure Handling Notes

Two guard scenarios to test the dispatcher results directory checks.

## Scenario A – ResultsPath is an existing file

- Prepare a placeholder (`blocked-results.txt`).
- Run dispatcher with `-ResultsPath blocked-results.txt`.
- Expect non-zero exit, terminating error referencing guard crumb (`tests/results/_diagnostics/guard.json`).
- Crumb `path` should match the resolved file.
- `_invoker` directory should remain absent when it did not exist beforehand.

## Scenario B – ResultsPath is read-only directory

- Create directory, set `ReadOnly` attribute.
- Run dispatcher pointing at that directory.
- Expect same behaviour as Scenario A, crumbs pointing to the directory.

## Assertions

- Capture stdout/stderr and verify terminating error text.
- Validate guard crumb schema (`docs/schema/generated/dispatcher-results-guard.schema.json`).
- Ensure no `pester-results.xml` or `pester-summary.json` are written in the blocked path.
