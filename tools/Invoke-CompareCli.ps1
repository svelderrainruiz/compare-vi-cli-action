[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Category,
  [Parameter()][string]$IncludeIntegration = 'true',
  [Parameter()][ValidateNotNullOrEmpty()][string]$ResultsRoot = 'tests/results/categories'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IncludePatterns {
  param([string]$Name)
  switch ($Name.ToLowerInvariant()) {
    'dispatcher' { return @('Invoke-PesterTests*.ps1','PesterAvailability.Tests.ps1','NestedDispatcher*.Tests.ps1') }
    'fixtures'   { return @('Fixtures.*.ps1','FixtureValidation*.ps1','FixtureSummary*.ps1','ViBinaryHandling.Tests.ps1','FixtureValidationDiff.Tests.ps1') }
    'schema'     { return @('Schema.*.ps1','SchemaLite*.ps1') }
    'comparevi'  { return @('CompareVI*.ps1','CanonicalCli.Tests.ps1','Args.Tokenization.Tests.ps1') }
    'loop'       { return @('CompareLoop*.ps1','Run-AutonomousIntegrationLoop*.ps1','LoopMetrics.Tests.ps1','Integration-ControlLoop*.ps1','IntegrationControlLoop*.ps1') }
    'psummary'   { return @('PesterSummary*.ps1','Write-PesterSummaryToStepSummary*.ps1','AggregationHints*.ps1') }
    'workflow'   { return @('Workflow*.ps1','On-FixtureValidationFail.Tests.ps1','Watch.FlakyRecovery.Tests.ps1','FunctionShadowing*.ps1','FunctionProxy.Tests.ps1','RunSummary.Tool*.ps1','Action.CompositeOutputs.Tests.ps1','Binding.MinRepro.Tests.ps1','ArtifactTracking*.ps1','Guard.*.Tests.ps1') }
    default      { return @('*.ps1') }
  }
}

$resultsDir = Join-Path $ResultsRoot $Category
if (-not (Test-Path -LiteralPath $resultsDir -PathType Container)) {
  New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$includePatterns = Get-IncludePatterns -Name $Category
$includePatterns = @($includePatterns | Where-Object { $_ })

Write-Host "[cli] category=$Category results=$resultsDir include=$($includePatterns -join ',')" -ForegroundColor Cyan

& "$PSScriptRoot/Invoke-PesterTests.ps1" `
  -TestsPath 'tests' `
  -IncludeIntegration $IncludeIntegration `
  -ResultsPath $resultsDir `
  -EmitFailuresJsonAlways `
  -IncludePatterns $includePatterns
$pesterExit = $LASTEXITCODE

$summaryPath = Join-Path $resultsDir 'pester-summary.json'
$cliRun = [ordered]@{
  schema              = 'compare-cli-run/v1'
  generatedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
  category            = $Category
  includeIntegration  = [bool]([System.Convert]::ToBoolean($IncludeIntegration))
  resultsDir          = $resultsDir
  summaryPath         = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { $summaryPath } else { $null }
  status              = 'unknown'
  exitCode            = $pesterExit
}
if ($cliRun.summaryPath) {
  try {
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $cliRun.status = if ($summary.failed -gt 0 -or $summary.errors -gt 0) { 'fail' } else { 'ok' }
    $cliRun.summary = [ordered]@{
      total      = $summary.total
      passed     = $summary.passed
      failed     = $summary.failed
      errors     = $summary.errors
      skipped    = $summary.skipped
      duration_s = $summary.duration_s
    }
  } catch {
    Write-Warning "[cli] failed to parse pester summary for $Category: $_"
  }
}

$cliRunPath = Join-Path $resultsDir 'cli-run.json'
$cliRun | ConvertTo-Json -Depth 4 | Out-File -FilePath $cliRunPath -Encoding utf8
Write-Host "[cli] wrote summary to $cliRunPath"

exit $pesterExit
