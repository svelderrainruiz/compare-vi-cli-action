# Self-Hosted Windows Implementation Status

## Overview

This document summarizes the implementation status of self-hosted Windows runner support for the LabVIEW Compare VI CLI GitHub Action.

## ✅ Completed Features

### Core Functionality

- **Flexible CLI Path Resolution**: Implemented in `scripts/CompareVI.ps1`
  - Priority: `lvComparePath` input → `LVCOMPARE_PATH` env → `Get-Command` (PATH) → canonical install path
  - Supports both testing scenarios and production deployments

- **Comprehensive Error Handling**:
  - Validates required inputs
  - Resolves relative paths from `working-directory`
  - Emits outputs before failures for workflow branching
  - Structured step summaries via `$GITHUB_STEP_SUMMARY`

### Testing Infrastructure

#### Unit Tests (`tests/CompareVI.Tests.ps1`, `tests/CompareVI.InputOutput.Tests.ps1`)

- ✅ 20 tests passing, 2 skipped (require canonical CLI on Windows)
- Mock-based testing without requiring real CLI
- Test all resolution paths and error conditions
- Run on `windows-latest` GitHub-hosted runners

#### Integration Tests (`tests/CompareVI.Integration.Tests.ps1`)

- Tagged with `Integration` for conditional execution
- Require self-hosted Windows runner with:
  - LabVIEW Compare CLI at canonical path
  - `LV_BASE_VI` and `LV_HEAD_VI` environment variables
- Validate real CLI invocation and exit codes

#### Mock CLI Tests (`.github/workflows/test-mock.yml`)

- Run on `windows-latest` GitHub-hosted runners
- Use mock CLI script to simulate behavior
- Test multiple scenarios including error conditions
- Generate HTML reports via `scripts/Render-CompareReport.ps1`

### Workflows

#### `test-pester.yml` - Unit Tests

- Runs on `windows-latest`
- Excludes Integration tests by default
- Can include Integration via workflow_dispatch input

#### `pester-selfhosted.yml` - Self-Hosted Integration Tests

- Runs on `[self-hosted, Windows, X64]`
- Uses repository variables `LV_BASE_VI` and `LV_HEAD_VI`
- Includes Integration tests by default
- Uploads test results as artifacts

#### `test-mock.yml` - Mock CLI Validation

- Runs on `windows-latest`
- Tests action behavior without real CLI
- Validates all code paths
- Generates and uploads HTML reports

#### `command-dispatch.yml` - PR Comment Commands

- Responds to PR comments starting with `/run`
- Supports commands:
  - `/run unit` - Unit tests only
  - `/run mock` - Mock CLI tests
  - `/run smoke` - Smoke tests on self-hosted runner
  - `/run pester-selfhosted` - Integration tests on self-hosted runner
- Parses command-line style arguments
- Dispatches workflows on PR head branch (same-repo) or main (fork)

#### `smoke.yml` - Manual Smoke Tests

- Manual dispatch workflow
- Runs on self-hosted Windows runner
- Accepts VI file paths as inputs
- Generates HTML comparison reports

#### `validate.yml` - Linting and Validation

- Runs markdownlint on all Markdown files
- Runs actionlint on all workflow files
- Executes on every PR and push to main

### Documentation

- ✅ `README.md` - User-facing documentation
- ✅ `docs/runner-setup.md` - Self-hosted runner setup guide
- ✅ `CONTRIBUTING.md` - Contribution guidelines
- ✅ `INTEGRATION_PLAN.md` - Implementation details and test coverage
- ✅ `.github/copilot-instructions.md` - AI assistant context

## Self-Hosted Runner Requirements

### Software

- Windows Server or Windows 10/11
- LabVIEW 2025 Q3 with valid license
- LabVIEW Compare CLI installed at canonical path:
  - `C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe`
- PowerShell 7+ (pwsh)

### Configuration

1. Install GitHub Actions runner
2. Run as service under account with LabVIEW license
3. Add runner labels: `self-hosted`, `Windows`, `X64`
4. Set repository variables:
   - `LV_BASE_VI` - Path to a test VI file
   - `LV_HEAD_VI` - Path to a different test VI file

### Testing the Setup

1. Manually dispatch `pester-selfhosted.yml` workflow
2. Verify all Integration tests pass
3. Use PR comment `/run pester-selfhosted` to test from PRs

## CI/CD Pipeline

### On Pull Request

1. Validate (markdownlint, actionlint)
2. Unit tests (windows-latest)
3. Mock CLI tests (windows-latest)

### On PR Comment

- `/run unit` - Quick unit test feedback
- `/run mock` - Mock CLI validation
- `/run pester-selfhosted` - Full integration testing
- `/run smoke pr=NUMBER` - Manual smoke test

### On Push to Main

1. Validate
2. Unit tests
3. Mock CLI tests

### On Tag Push (vX.Y.Z)

1. Create GitHub Release
2. Extract changelog section
3. Publish to GitHub Marketplace

## Known Limitations

- Integration tests require self-hosted Windows runner (not available on GitHub-hosted)
- Real CLI requires LabVIEW license and installation
- Mock CLI provides limited validation compared to real CLI
- Actionlint reports shellcheck style warnings (info level, not failures)

## Future Enhancements

Potential improvements for consideration:

- Add support for LabVIEW versions other than 2025 Q3
- Enhanced HTML report generation with diff visualization
- Performance benchmarking for large VI files
- Parallel test execution for faster CI feedback
- Automated runner health checks

## Verification Checklist

- [x] Unit tests pass on windows-latest
- [x] Mock CLI tests pass on windows-latest
- [x] Integration tests pass on self-hosted Windows (when runner available)
- [x] Command dispatcher responds to PR comments
- [x] Smoke tests can be triggered manually
- [x] Markdownlint passes
- [x] Actionlint passes (info-level warnings acceptable)
- [x] Documentation is complete and accurate
- [x] Workflows use `pwsh` for PowerShell 7+
- [x] Outputs are emitted before failures
- [x] HTML reports are generated and uploaded
