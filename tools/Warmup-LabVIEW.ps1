<#
.SYNOPSIS
  Compatibility wrapper for Warmup-LabVIEWRuntime.ps1 (deprecated entry point).

.DESCRIPTION
  For backward compatibility, this script forwards to tools/Warmup-LabVIEWRuntime.ps1
  with a subset of parameters. New automation should call Warmup-LabVIEWRuntime.ps1
  directly.

.PARAMETER LabVIEWExePath
  Path to LabVIEW.exe (forwarded).

.PARAMETER MinimumSupportedLVVersion
  Version used to derive LabVIEW path (forwarded).

.PARAMETER SupportedBitness
  Bitness (forwarded).

.PARAMETER TimeoutSeconds
  Startup timeout (forwarded).

.PARAMETER IdleWaitSeconds
  Idle gate after detection (forwarded).

.PARAMETER JsonLogPath
  NDJSON event log path (forwarded).

.PARAMETER KillOnTimeout
  Forcibly terminate on timeout (forwarded).

.PARAMETER DryRun
  Plan only (forwarded).
#>
[CmdletBinding()]
param(
  [string]$LabVIEWPath,
  [string]$MinimumSupportedLVVersion,
  [ValidateSet('32','64')][string]$SupportedBitness,
  [int]$TimeoutSeconds = 30,
  [int]$IdleWaitSeconds = 2,
  [string]$JsonLogPath,
  [switch]$KillOnTimeout,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runtime = Join-Path (Split-Path -Parent $PSCommandPath) 'Warmup-LabVIEWRuntime.ps1'
if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) {
  Write-Error "Warmup-LabVIEWRuntime.ps1 not found next to this script"
  exit 1
}

Write-Host '[deprecated] Warmup-LabVIEW.ps1 forwarding to Warmup-LabVIEWRuntime.ps1' -ForegroundColor DarkYellow

& $runtime `
  -LabVIEWPath $LabVIEWPath `
  -MinimumSupportedLVVersion $MinimumSupportedLVVersion `
  -SupportedBitness $SupportedBitness `
  -TimeoutSeconds $TimeoutSeconds `
  -IdleWaitSeconds $IdleWaitSeconds `
  -JsonLogPath $JsonLogPath `
  -KillOnTimeout:$KillOnTimeout.IsPresent `
  -DryRun:$DryRun.IsPresent

exit $LASTEXITCODE
