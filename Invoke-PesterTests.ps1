#Requires -Version 7.0
<#
.SYNOPSIS
    Pester test dispatcher for compare-vi-cli-action
.DESCRIPTION
    This dispatcher is called by the open-source run-pester-tests action.
    It handles running Pester tests with the appropriate configuration.
    Assumes Pester is already installed on the self-hosted runner.
.PARAMETER TestsPath
    Path to the directory containing test scripts (default: tests)
.PARAMETER IncludeIntegration
    Include Integration-tagged tests (default: false)
.PARAMETER ResultsPath
    Path to directory where results should be written (default: tests/results)
#>

param(
  [Parameter(Mandatory = $false)]
  [string]$TestsPath = 'tests',

  [Parameter(Mandatory = $false)]
  [string]$IncludeIntegration = 'false',

  [Parameter(Mandatory = $false)]
  [string]$ResultsPath = 'tests/results'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Pester Test Dispatcher ==="
Write-Host "Tests Path: $TestsPath"
Write-Host "Include Integration: $IncludeIntegration"
Write-Host "Results Path: $ResultsPath"

# Resolve paths relative to script root
$root = $PSScriptRoot
$testsDir = Join-Path $root $TestsPath
$resultsDir = Join-Path $root $ResultsPath

# Ensure directories exist
if (-not (Test-Path -LiteralPath $testsDir)) {
  Write-Error "Tests directory not found: $testsDir"
  exit 1
}
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

# Check for Pester v5+ availability (should be pre-installed on self-hosted runner)
$pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0.0' } | Select-Object -First 1
if (-not $pesterModule) {
  Write-Error "Pester v5+ not found. Please install Pester on the self-hosted runner: Install-Module -Name Pester -MinimumVersion 5.0.0 -Force"
  exit 1
}

Import-Module Pester -MinimumVersion 5.0.0 -Force
Write-Host "Using Pester $((Get-Module Pester).Version)"

# Build Pester configuration
$conf = New-PesterConfiguration
$conf.Run.Path = $testsDir

# Handle include-integration parameter (string or boolean)
$includeIntegrationBool = $false
if ($IncludeIntegration -is [string]) {
  $includeIntegrationBool = $IncludeIntegration -ieq 'true'
} elseif ($IncludeIntegration -is [bool]) {
  $includeIntegrationBool = $IncludeIntegration
}

if (-not $includeIntegrationBool) {
  Write-Host "Excluding Integration-tagged tests"
  $conf.Filter.ExcludeTag = @('Integration')
} else {
  Write-Host "Including Integration-tagged tests"
}

$conf.Output.Verbosity = 'Detailed'
$conf.TestResult.Enabled = $true
$conf.TestResult.OutputFormat = 'NUnitXml'
$conf.TestResult.OutputPath = 'pester-results.xml'  # Filename relative to CWD

# Run from results directory so XML lands there
Write-Host "Running Pester tests..."
Push-Location -LiteralPath $resultsDir
try {
  $result = Invoke-Pester -Configuration $conf
}
finally {
  Pop-Location
}

# Derive summary from NUnit XML
$xmlPath = Join-Path $resultsDir 'pester-results.xml'
if (-not (Test-Path -LiteralPath $xmlPath)) {
  Write-Error "Pester result XML not found at: $xmlPath"
  exit 1
}

[xml]$doc = Get-Content -LiteralPath $xmlPath -Raw
$rootNode = $doc.'test-results'
[int]$total = $rootNode.total
[int]$failed = $rootNode.failures
[int]$errors = $rootNode.errors
$passed = $total - $failed - $errors
$skipped = [int]$rootNode.'not-run'

$summary = @(
  "=== Pester Test Summary ===",
  "Total: $total",
  "Passed: $passed",
  "Failed: $failed",
  "Errors: $errors",
  "Skipped: $skipped"
) -join [Environment]::NewLine

Write-Host $summary
$summary | Out-File -FilePath (Join-Path $resultsDir 'pester-summary.txt') -Encoding utf8

# Exit with failure if tests failed
if ($failed -gt 0 -or $errors -gt 0) {
  Write-Error "Tests failed: $failed failures, $errors errors"
  exit 1
}

Write-Host "All tests passed!"
exit 0
