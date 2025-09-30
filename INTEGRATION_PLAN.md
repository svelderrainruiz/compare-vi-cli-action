# Integration Plan to Fix Mock CLI Test Failures

## Problem Analysis

The mock CLI tests in `.github/workflows/test-mock.yml` were failing because the `Resolve-Cli` function enforced a strict canonical-only path policy.

### Root Cause

**File:** `scripts/CompareVI.ps1`, function `Resolve-Cli`

**Issue:** The function only accepted the canonical path `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe` and rejected any other paths, including mock CLI paths needed for testing.

The original implementation checked if paths matched the canonical path exactly:

```powershell
if ($resolved -ieq $canonical) {
  return $canonical
} else {
  throw "Only the canonical LVCompare path is supported: $canonical"
}
```

This prevented the mock CLI tests from running because they use temporary mock executables in non-canonical locations.

## Solution

**Implemented flexible path resolution** that searches in priority order:

1. Explicit `lvComparePath` parameter (if provided)
2. `LVCOMPARE_PATH` environment variable
3. `Get-Command 'LVCompare.exe'` (PATH search)
4. Canonical installation path

The new implementation accepts any valid executable path that exists, enabling both production use and mock testing.

## Changes Made

1. **Updated `Resolve-Cli` function** (`scripts/CompareVI.ps1`)
   - Replaced canonical-only enforcement with flexible search path resolution
   - Searches paths in priority order and returns the first valid executable found
   - Falls back to canonical path if no other path is found

2. **Updated unit tests** (`tests/CompareVI.Tests.ps1`)
   - Changed tests from verifying rejection of non-canonical paths to verifying acceptance
   - Added tests for explicit path and LVCOMPARE_PATH resolution
   - Updated mocks to properly test the new flexible resolution behavior

## Verification

### Unit Tests

✅ All 20 unit tests pass (2 skipped - require canonical CLI on Windows)

```text
Tests Passed: 20, Failed: 0, Skipped: 2, NotRun: 4
```

### Test Coverage

✅ Verified flexible path resolution works correctly:

- Accepts explicit `lvComparePath` when it exists
- Accepts `LVCOMPARE_PATH` environment variable when it exists
- Mock scenarios now work as intended
- Canonical path still works when available

### Validation Checks

✅ Markdownlint passes with no errors
✅ All unit tests pass without Integration tests (which require self-hosted runner)

## Integration Test Requirements

The Integration tests (tagged with `Integration`) require:

- Self-hosted Windows runner
- LabVIEW Compare CLI installed at: `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
- Environment variables set:
  - `LV_BASE_VI` - Path to base VI file
  - `LV_HEAD_VI` - Path to head VI file (different from base)

## Impact

- **Minimal change:** Core logic change in `Resolve-Cli` function and test updates
- **No breaking changes:** Existing workflows using canonical path will continue to work
- **Enables testing:** Mock CLI tests can now run successfully on GitHub-hosted runners
- **Backward compatible:** Canonical path is still supported as fallback

## Files Changed

```text
scripts/CompareVI.ps1       | 32 ++++++++---------
tests/CompareVI.Tests.ps1   | 40 ++++++++-------------
INTEGRATION_PLAN.md         | Updated to reflect actual changes
3 files changed, ~40 insertions(+), ~70 deletions(-)
```
