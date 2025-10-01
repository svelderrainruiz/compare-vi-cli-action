#Requires -Version 7.0
<#
.SYNOPSIS
    Pester test dispatcher for compare-vi-cli-action
.DESCRIPTION
    This dispatcher is called directly by the pester-selfhosted.yml workflow.
    It handles running Pester tests with the appropriate configuration.
    Assumes Pester is already installed on the self-hosted runner.
.PARAMETER TestsPath
    Path to the directory containing test scripts (default: tests)
.PARAMETER IncludeIntegration
    Include Integration-tagged tests (default: false). Accepts 'true'/'false' string or boolean.
.PARAMETER ResultsPath
    Path to directory where results should be written (default: tests/results)
.EXAMPLE
    ./Invoke-PesterTests.ps1 -TestsPath tests -IncludeIntegration true -ResultsPath tests/results
.EXAMPLE
    ./Invoke-PesterTests.ps1 -IncludeIntegration false
.NOTES
    Requires Pester v5.0.0 or later to be pre-installed on the runner.
    Exit codes: 0 = success, 1 = failure (test failures or execution errors)
#>

param(
  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string]$TestsPath = 'tests',

  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string]$IncludeIntegration = 'false',

  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string]$ResultsPath = 'tests/results'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Display dispatcher information
Write-Host "=== Pester Test Dispatcher ===" -ForegroundColor Cyan
Write-Host "Script Version: 1.0.0"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Tests Path: $TestsPath"
Write-Host "  Include Integration: $IncludeIntegration"
Write-Host "  Results Path: $ResultsPath"
Write-Host ""

# Resolve paths relative to script root
$root = $PSScriptRoot
if (-not $root) {
  Write-Error "Unable to determine script root directory"
  exit 1
}

$testsDir = Join-Path $root $TestsPath
$resultsDir = Join-Path $root $ResultsPath

Write-Host "Resolved Paths:" -ForegroundColor Yellow
Write-Host "  Script Root: $root"
Write-Host "  Tests Directory: $testsDir"
Write-Host "  Results Directory: $resultsDir"
Write-Host ""

# Validate tests directory exists
if (-not (Test-Path -LiteralPath $testsDir -PathType Container)) {
  Write-Error "Tests directory not found: $testsDir"
  Write-Host "Please ensure the tests directory exists and contains test files." -ForegroundColor Red
  exit 1
}

# Count test files
$testFiles = Get-ChildItem -Path $testsDir -Filter '*.Tests.ps1' -Recurse -File
Write-Host "Found $($testFiles.Count) test file(s) in tests directory" -ForegroundColor Green

# Create results directory if it doesn't exist
try {
  New-Item -ItemType Directory -Force -Path $resultsDir -ErrorAction Stop | Out-Null
  Write-Host "Results directory ready: $resultsDir" -ForegroundColor Green
} catch {
  Write-Error "Failed to create results directory: $resultsDir. Error: $_"
  exit 1
}

Write-Host ""

# Check for Pester v5+ availability (should be pre-installed on self-hosted runner)
Write-Host "Checking for Pester availability..." -ForegroundColor Yellow
$pesterModule = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0.0' } | Select-Object -First 1

if (-not $pesterModule) {
  Write-Error "Pester v5+ not found."
  Write-Host ""
  Write-Host "Please install Pester on the self-hosted runner:" -ForegroundColor Yellow
  Write-Host "  Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser" -ForegroundColor Cyan
  Write-Host ""
  exit 1
}

Write-Host "Pester module found: v$($pesterModule.Version)" -ForegroundColor Green

# Import Pester module
try {
  Import-Module Pester -MinimumVersion 5.0.0 -Force -ErrorAction Stop
  $loadedPester = Get-Module Pester
  Write-Host "Using Pester v$($loadedPester.Version)" -ForegroundColor Green
} catch {
  Write-Error "Failed to import Pester module: $_"
  exit 1
}

Write-Host ""

# Build Pester configuration
Write-Host "Configuring Pester..." -ForegroundColor Yellow
$conf = New-PesterConfiguration

# Set test path
$conf.Run.Path = $testsDir

# Handle include-integration parameter (string or boolean)
$includeIntegrationBool = $false
if ($IncludeIntegration -is [string]) {
  $includeIntegrationBool = $IncludeIntegration -ieq 'true'
} elseif ($IncludeIntegration -is [bool]) {
  $includeIntegrationBool = $IncludeIntegration
}

if (-not $includeIntegrationBool) {
  Write-Host "  Excluding Integration-tagged tests" -ForegroundColor Cyan
  $conf.Filter.ExcludeTag = @('Integration')
} else {
  Write-Host "  Including Integration-tagged tests" -ForegroundColor Cyan
}

# Configure output
$conf.Output.Verbosity = 'Detailed'

# Configure test results
$conf.TestResult.Enabled = $true
$conf.TestResult.OutputFormat = 'NUnitXml'
$conf.TestResult.OutputPath = 'pester-results.xml'  # Filename relative to CWD

Write-Host "  Output Verbosity: Detailed" -ForegroundColor Cyan
Write-Host "  Result Format: NUnitXml" -ForegroundColor Cyan
Write-Host ""

# Run Pester tests from results directory so XML lands there
Write-Host "Executing Pester tests..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor DarkGray

$testStartTime = Get-Date

Push-Location -LiteralPath $resultsDir
try {
  $result = Invoke-Pester -Configuration $conf
  $testEndTime = Get-Date
  $testDuration = $testEndTime - $testStartTime
} catch {
  Write-Error "Pester execution failed: $_"
  exit 1
} finally {
  Pop-Location
}

Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Test execution completed in $($testDuration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
Write-Host ""

# Verify results file exists
$xmlPath = Join-Path $resultsDir 'pester-results.xml'
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) {
  Write-Error "Pester result XML not found at: $xmlPath"
  Write-Host "This may indicate a problem with test execution." -ForegroundColor Red
  exit 1
}

# Parse NUnit XML results
Write-Host "Parsing test results..." -ForegroundColor Yellow
try {
  [xml]$doc = Get-Content -LiteralPath $xmlPath -Raw -ErrorAction Stop
  $rootNode = $doc.'test-results'
  
  if (-not $rootNode) {
    Write-Error "Invalid NUnit XML format in results file"
    exit 1
  }
  
  [int]$total = $rootNode.total
  [int]$failed = $rootNode.failures
  [int]$errors = $rootNode.errors
  [int]$skipped = $rootNode.'not-run'
  $passed = $total - $failed - $errors
  
} catch {
  Write-Error "Failed to parse test results: $_"
  exit 1
}

# Generate summary
$summary = @(
  "=== Pester Test Summary ===",
  "Total Tests: $total",
  "Passed: $passed",
  "Failed: $failed",
  "Errors: $errors",
  "Skipped: $skipped",
  "Duration: $($testDuration.TotalSeconds.ToString('F2'))s"
) -join [Environment]::NewLine

Write-Host ""
Write-Host $summary -ForegroundColor $(if ($failed -eq 0 -and $errors -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

# Write summary to file
$summaryPath = Join-Path $resultsDir 'pester-summary.txt'
try {
  $summary | Out-File -FilePath $summaryPath -Encoding utf8 -ErrorAction Stop
  Write-Host "Summary written to: $summaryPath" -ForegroundColor Gray
} catch {
  Write-Warning "Failed to write summary file: $_"
}

Write-Host "Results written to: $xmlPath" -ForegroundColor Gray
Write-Host ""

# Exit with appropriate code
if ($failed -gt 0 -or $errors -gt 0) {
  Write-Host "❌ Tests failed: $failed failure(s), $errors error(s)" -ForegroundColor Red
  Write-Error "Test execution completed with failures"
  exit 1
}

Write-Host "✅ All tests passed!" -ForegroundColor Green
exit 0
