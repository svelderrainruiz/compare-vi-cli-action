param(
  [switch]$IncludeIntegration
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $root 'tests' 'results'
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

# Use a repo-local Pester to avoid conflicts with system Pester v3
$toolsModules = Join-Path $root 'tools' 'modules'
$pesterPath = Join-Path $toolsModules 'Pester'
if (-not (Test-Path -LiteralPath $pesterPath)) {
  Write-Host 'Installing Pester v5 locally under tools/modules...'
  New-Item -ItemType Directory -Force -Path $toolsModules | Out-Null
  Save-Module -Name Pester -RequiredVersion 5.4.0 -Path $toolsModules -Force
}

# Import Pester v5 explicitly
$importTarget = Get-ChildItem -Path $pesterPath -Directory | Sort-Object Name -Descending | Select-Object -First 1
Import-Module (Join-Path $importTarget.FullName 'Pester.psd1') -Force
Write-Host ("Using Pester {0}" -f (Get-Module Pester).Version)

# Build configuration
$conf = New-PesterConfiguration
$conf.Run.Path = (Join-Path $root 'tests')
if (-not $IncludeIntegration) {
  $conf.Filter.ExcludeTag = @('Integration')
}
$conf.Output.Verbosity = 'Detailed'
$conf.TestResult.Enabled = $true
$conf.TestResult.OutputFormat = 'NUnitXml'
$conf.TestResult.OutputPath = 'pester-results.xml'  # filename relative to CWD per Pester 5

# Run from results directory so XML lands there
Push-Location -LiteralPath $resultsDir
try {
  Invoke-Pester -Configuration $conf
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
$skipped = 0
$summary = @(
  "Tests Passed: $passed",
  "Tests Failed: $failed",
  "Tests Skipped: $skipped"
) -join [Environment]::NewLine
$summary | Tee-Object -FilePath (Join-Path $resultsDir 'pester-summary.txt')

if ($failed -gt 0 -or $errors -gt 0) { exit 1 }