#Requires -Version 7.0
<#!
.SYNOPSIS
  Emits a readiness report for CompareVI integration tests.
.DESCRIPTION
  Checks for canonical LVCompare.exe, optional LabVIEWCLI, and required environment variables.
  Produces structured console output and a JSON file if -JsonPath provided.
.PARAMETER JsonPath
  Optional path to write JSON readiness report.
.PARAMETER VerboseOutput
  Switch to emit detailed diagnostic lines.
.EXAMPLE
  ./scripts/Test-IntegrationEnvironment.ps1 -JsonPath tests/results/integration-env.json
#>
param(
  [string]$JsonPath,
  [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
$labviewCli64 = 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEWCLI.exe'
$labviewCli32 = 'C:\Program Files (x86)\National Instruments\LabVIEW 2025\LabVIEWCLI.exe'

function Test-FilePresent($path) {
  [pscustomobject]@{
    Path = $path
    Exists = (Test-Path -LiteralPath $path -PathType Leaf)
  }
}

$lvCompare = Test-FilePresent $canonical
$cliCandidate = Test-FilePresent $labviewCli64
if (-not $cliCandidate.Exists) { $cliCandidate = Test-FilePresent $labviewCli32 }

$baseEnv = $env:LV_BASE_VI
$headEnv = $env:LV_HEAD_VI

$baseOk = $false
$headOk = $false
if ($baseEnv) { $baseOk = Test-Path -LiteralPath $baseEnv -PathType Leaf }
if ($headEnv) { $headOk = Test-Path -LiteralPath $headEnv -PathType Leaf }

$prereqsOk = $lvCompare.Exists -and $baseOk -and $headOk

$result = [pscustomobject]@{
  TimestampUtc            = (Get-Date).ToUniversalTime().ToString('o')
  CanonicalLVComparePath  = $canonical
  LVComparePresent        = $lvCompare.Exists
  LabVIEWCLIPath          = if ($cliCandidate.Exists) { $cliCandidate.Path } else { $null }
  LabVIEWCLIPresent       = $cliCandidate.Exists
  LV_BASE_VI              = $baseEnv
  LV_BASE_VI_Exists       = $baseOk
  LV_HEAD_VI              = $headEnv
  LV_HEAD_VI_Exists       = $headOk
  CompareVIPrereqsReady   = $prereqsOk
}

Write-Host '=== CompareVI Integration Environment Check ===' -ForegroundColor Cyan
Write-Host ('LVCompare canonical path : {0} ({1})' -f $canonical, $(if ($lvCompare.Exists) { 'FOUND' } else { 'MISSING' }))
Write-Host ('LabVIEWCLI path         : {0}' -f $(if ($cliCandidate.Exists) { $cliCandidate.Path } else { '[not found]' }))
Write-Host ('LV_BASE_VI              : {0} ({1})' -f ($(if ($baseEnv) { $baseEnv } else { '[unset]' })), $(if ($baseOk) { 'OK' } else { 'MISSING' }))
Write-Host ('LV_HEAD_VI              : {0} ({1})' -f ($(if ($headEnv) { $headEnv } else { '[unset]' })), $(if ($headOk) { 'OK' } else { 'MISSING' }))
Write-Host ('Prerequisites ready     : {0}' -f $prereqsOk) -ForegroundColor $(if ($prereqsOk) { 'Green' } else { 'Yellow' })

if ($VerboseOutput) {
  Write-Host "-- Raw JSON --" -ForegroundColor DarkGray
  $result | ConvertTo-Json -Depth 5 | Write-Host
}

if ($JsonPath) {
  $dir = Split-Path -Parent $JsonPath
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $JsonPath -Encoding utf8
  Write-Host ("JSON written: {0}" -f (Resolve-Path $JsonPath).Path) -ForegroundColor Gray
}

# Exit code: 0 if prereqs ready, 1 otherwise (non-fatal informational)
if (-not $prereqsOk) { exit 1 } else { exit 0 }
