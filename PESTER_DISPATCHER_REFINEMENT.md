# Pester Test Dispatcher Refinement

## Overview

This document summarizes the refinements made to the Pester test execution architecture to properly integrate with the open-source `run-pester-tests` action.

## Changes Made

### 1. Root-Level Test Dispatcher (`Invoke-PesterTests.ps1`)

**Purpose:** Entry point for the open-source `run-pester-tests` action from `LabVIEW-Community-CI-CD/open-source`.

**Location:** Repository root

**Key Features:**

- Accepts parameters matching the open-source action interface:
  - `TestsPath` (default: `tests`)
  - `IncludeIntegration` (default: `false`)
  - `ResultsPath` (default: `tests/results`)
- Assumes Pester v5+ is pre-installed on self-hosted runners
- Generates NUnit XML and summary text files
- Provides detailed progress logging

**Usage:**

```powershell
# Called automatically by the open-source action
./Invoke-PesterTests.ps1 -TestsPath tests -IncludeIntegration true -ResultsPath tests/results
```

### 2. Local Test Dispatcher (`tools/Run-Pester.ps1`)

**Purpose:** Direct test execution for GitHub-hosted workflows and local development.

**Usage:**

```powershell
# Unit tests only
./tools/Run-Pester.ps1

# Include Integration tests
./tools/Run-Pester.ps1 -IncludeIntegration
```

**Features:**

- Auto-discovers and installs Pester if not found
- Used by `test-pester.yml` and `pester-integration-on-label.yml`
- No external dependencies required

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Dispatch                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├─────────────────────────────────┐
                              │                                 │
                    ┌─────────▼──────────┐        ┌────────────▼──────────┐
                    │  GitHub-Hosted     │        │  Self-Hosted Windows   │
                    │  (windows-latest)  │        │  [self-hosted, Win]    │
                    └─────────┬──────────┘        └────────────┬──────────┘
                              │                                 │
                    ┌─────────▼──────────┐        ┌────────────▼──────────┐
                    │  test-pester.yml   │        │ pester-selfhosted.yml │
                    │  (direct call)     │        │ (open-source action)  │
                    └─────────┬──────────┘        └────────────┬──────────┘
                              │                                 │
                    ┌─────────▼──────────┐        ┌────────────▼──────────┐
                    │ tools/Run-Pester   │        │ open-source action    │
                    │   .ps1             │        │ run-pester-tests      │
                    └─────────┬──────────┘        └────────────┬──────────┘
                              │                                 │
                              │                   ┌─────────────▼──────────┐
                              │                   │ Invoke-PesterTests.ps1 │
                              │                   │ (repository root)      │
                              │                   └─────────────┬──────────┘
                              │                                 │
                              └─────────────┬───────────────────┘
                                            │
                                  ┌─────────▼──────────┐
                                  │  Pester v5+ Engine │
                                  └─────────┬──────────┘
                                            │
                                  ┌─────────▼──────────┐
                                  │  tests/*.Tests.ps1 │
                                  └────────────────────┘
```

## Workflow Integration

### Self-Hosted Runner Workflow (`pester-selfhosted.yml`)

Uses the open-source action, which delegates to `Invoke-PesterTests.ps1`:

```yaml
- name: Run Pester on self-hosted via open-source action
  uses: LabVIEW-Community-CI-CD/open-source/actions/run-pester-tests@actions
  with:
    tests-path: tests
    include-integration: ${{ inputs.include_integration }}
    results-path: tests/results
```

### GitHub-Hosted Workflow (`test-pester.yml`)

Directly calls the local dispatcher:

```yaml
- name: Run unit tests
  shell: pwsh
  run: |
    if ('${{ inputs.include_integration }}' -ieq 'true') {
      ./tools/Run-Pester.ps1 -IncludeIntegration
    } else {
      ./tools/Run-Pester.ps1
    }
```

## Prerequisites

### For Self-Hosted Runners

- **Pester v5+** must be pre-installed
  - Install: `Install-Module -Name Pester -MinimumVersion 5.0.0 -Force`
  - Verify: `Get-Module -ListAvailable Pester`
- PowerShell 7+
- LabVIEW Compare CLI at canonical path (for Integration tests)
- Repository variables: `LV_BASE_VI`, `LV_HEAD_VI`

### For GitHub-Hosted Runners

- Pester is auto-installed by the workflow
- No additional setup required

## Testing the Setup

### Manual Dispatch

1. Navigate to Actions → "Pester (self-hosted, real CLI)"
2. Click "Run workflow"
3. Set `include_integration` to `true` or `false`
4. Run and verify artifacts are uploaded

### PR Comment Trigger

Comment on a PR:

```text
/run pester-selfhosted
```

Verifies:

- Command dispatcher workflow triggers correctly
- Open-source action is invoked
- Dispatcher script executes
- Results are uploaded as artifacts

## Validation Checklist

- [x] Root dispatcher created at `Invoke-PesterTests.ps1`
- [x] Dispatcher parameters match open-source action interface
- [x] Documentation updated (SELFHOSTED_CI_SETUP.md, IMPLEMENTATION_STATUS.md)
- [x] Workflow comments clarify dispatcher delegation
- [x] Markdown linting passes
- [x] Actionlint passes on all workflows
- [x] .gitignore updated to exclude development tools
- [ ] Integration test execution on self-hosted runner (requires hardware)
- [ ] Validation with real LabVIEW CLI (requires self-hosted setup)

## Benefits

1. **Clear Separation of Concerns:**
   - GitHub-hosted workflows use self-contained local dispatcher
   - Self-hosted workflows delegate to open-source shared action

2. **Consistent Interface:**
   - Both dispatchers accept similar parameters
   - Both generate standard NUnit XML output

3. **Maintainability:**
   - Open-source action handles environment validation
   - Repository-specific dispatcher focuses on test execution
   - Documented delegation pattern prevents confusion

4. **Flexibility:**
   - Can run tests locally with either dispatcher
   - Can trigger via workflow dispatch or PR comments
   - Supports both unit and integration tests

## Troubleshooting

### Dispatcher Not Found

**Symptom:** Open-source action fails with "script not found"

**Solution:** Ensure `Invoke-PesterTests.ps1` exists at repository root

### Pester Not Found

**Symptom:** Dispatcher fails with "Pester v5+ not found"

**Solution:**

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
```

### Parameter Mismatch

**Symptom:** Dispatcher receives unexpected parameter values

**Solution:** Verify open-source action passes parameters as strings, not booleans

## References

- [Self-Hosted CI/CD Setup Guide](./docs/SELFHOSTED_CI_SETUP.md)
- [Implementation Status](./IMPLEMENTATION_STATUS.md)
- [End-to-End Testing Guide](./docs/E2E_TESTING_GUIDE.md)
- [Open-Source Actions Repository](https://github.com/LabVIEW-Community-CI-CD/open-source)
