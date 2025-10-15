<#
.SYNOPSIS
  Thin wrapper for TestStand: warmup LabVIEW runtime, run LVCompare, and optionally close.

.DESCRIPTION
  Sequentially invokes Warmup-LabVIEWRuntime.ps1 (to ensure LabVIEW readiness), then
  Invoke-LVCompare.ps1 to perform a deterministic compare, and finally optional close helpers.
  Writes a session-index.json with pointers to emitted crumbs and artifacts.

.PARAMETER BaseVi
  Base VI path.

.PARAMETER HeadVi
  Head VI path.

.PARAMETER LabVIEWExePath
  Path to LabVIEW.exe (pinned version/bitness recommended).

.PARAMETER LVCompareExePath
  Path to LVCompare.exe (defaults to canonical install when omitted).

.PARAMETER OutputRoot
  Root folder for all outputs (default tests/results/teststand-session).

.PARAMETER Warmup
  Controls LabVIEW warmup behaviour. `detect` (default) warms up when the helper
  script is available, `spawn` forces a fresh warmup cycle (StopAfterWarmup),
  and `skip` bypasses warmup entirely.

.PARAMETER RenderReport
  Generate compare-report.html during compare.

.PARAMETER Flags
  Additional LVCompare flags forwarded to Invoke-LVCompare.ps1.

.PARAMETER ReplaceFlags
  Replace the default LVCompare flags with the provided -Flags values.

.PARAMETER CloseLabVIEW
  Attempt graceful LabVIEW close via tools/Close-LabVIEW.ps1 at the end.

.PARAMETER CloseLVCompare
  Attempt LVCompare cleanup via tools/Close-LVCompare.ps1 at the end.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$BaseVi,
  [Parameter(Mandatory)][string]$HeadVi,
  [Alias('LabVIEWPath')]
  [string]$LabVIEWExePath,
  [Alias('LVCompareExePath')]
  [string]$LVComparePath,
  [string]$OutputRoot = 'tests/results/teststand-session',
  [ValidateSet('detect','spawn','skip')]
  [string]$Warmup = 'detect',
  [string[]]$Flags,
  [switch]$ReplaceFlags,
  [switch]$RenderReport,
  [switch]$CloseLabVIEW,
  [switch]$CloseLVCompare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Dir([string]$p){ if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

$repo = (Resolve-Path '.').Path

# Resolve OutputRoot to absolute path for deterministic writes
if (-not ([System.IO.Path]::IsPathRooted($OutputRoot))) {
  $OutputRoot = Join-Path $repo $OutputRoot
}

$paths = [ordered]@{
  warmupDir = Join-Path $OutputRoot '_warmup'
  compareDir = Join-Path $OutputRoot 'compare'
}
New-Dir $paths.warmupDir
New-Dir $paths.compareDir

$baseLeaf = Split-Path -Path $BaseVi -Leaf
$headLeaf = Split-Path -Path $HeadVi -Leaf
$sameName = [string]::Equals($baseLeaf, $headLeaf, [System.StringComparison]::OrdinalIgnoreCase)
$policy = $env:LVCI_COMPARE_POLICY
$autoCli = $false
if ($sameName -and $policy -ne 'lv-only') {
  $autoCli = $true
  if ($Warmup -ne 'skip') {
    Write-Host "Harness: skipping warmup for same-name VIs (CLI path auto-selected)." -ForegroundColor Gray
    $Warmup = 'skip'
  }
}

$warmupLog = Join-Path $paths.warmupDir 'labview-runtime.ndjson'
$compareLog = Join-Path $paths.compareDir 'compare-events.ndjson'
$capPath = Join-Path $paths.compareDir 'lvcompare-capture.json'
$reportPath = Join-Path $paths.compareDir 'compare-report.html'
$cap = $null
$warmupRan = $false
$err = $null
$closeLVCompareScript = Join-Path $repo 'tools' 'Close-LVCompare.ps1'
$closeLabVIEWScript = Join-Path $repo 'tools' 'Close-LabVIEW.ps1'

try {
  # 1) Warmup LabVIEW runtime (optional)
  if ($Warmup -ne 'skip') {
    $warmupScript = Join-Path $repo 'tools' 'Warmup-LabVIEWRuntime.ps1'
    if (-not (Test-Path -LiteralPath $warmupScript)) { throw "Warmup-LabVIEWRuntime.ps1 not found at $warmupScript" }
    $warmParams = @{ JsonLogPath = $warmupLog }
    if ($LabVIEWExePath) { $warmParams.LabVIEWPath = $LabVIEWExePath }
    try {
      & $warmupScript @warmParams | Out-Null
      $warmupRan = $true
    } catch {
      $err = $_.Exception.Message
      throw
    }
  }

  # 2) Invoke LVCompare (deterministic)
  $invoke = Join-Path $repo 'tools' 'Invoke-LVCompare.ps1'
  if (-not (Test-Path -LiteralPath $invoke)) { throw "Invoke-LVCompare.ps1 not found at $invoke" }
  $invokeParams = @{
    BaseVi      = $BaseVi
    HeadVi      = $HeadVi
    OutputDir   = $paths.compareDir
    JsonLogPath = $compareLog
    RenderReport= $RenderReport.IsPresent
  }
  if ($LabVIEWExePath) { $invokeParams.LabVIEWExePath = $LabVIEWExePath }
  if ($LVComparePath) { $invokeParams.LVComparePath = $LVComparePath }
  if ($Flags) { $invokeParams.Flags = $Flags }
  if ($ReplaceFlags) { $invokeParams.ReplaceFlags = $true }
  & $invoke @invokeParams | Out-Null
  if (Test-Path -LiteralPath $capPath) { $cap = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json }
} catch { $err = $_.Exception.Message }
finally {
  if ($CloseLVCompare -and (Test-Path -LiteralPath $closeLVCompareScript)) {
    try { & $closeLVCompareScript | Out-Null } catch {}
  }
  if ($CloseLabVIEW -and (Test-Path -LiteralPath $closeLabVIEWScript)) {
    try { & $closeLabVIEWScript -MinimumSupportedLVVersion '2025' -SupportedBitness '64' | Out-Null } catch {}
  }
}

# 4) Session index (always write)
$reportExists = Test-Path -LiteralPath $reportPath -PathType Leaf
$warmupNode = [ordered]@{
  mode   = $Warmup
  events = if ($warmupRan) { $warmupLog } else { $null }
}
$compareNode = [ordered]@{
  events  = $compareLog
  capture = $capPath
  report  = $reportExists
}
if ($cap) {
  if ($cap.command)   { $compareNode.command = $cap.command }
  if ($cap.cliPath)   { $compareNode.cliPath = $cap.cliPath }
  if ($cap.environment -and $cap.environment.cli) { $compareNode.cli = $cap.environment.cli }
}
$compareNode.autoCli = $autoCli
$compareNode.sameName = $sameName
if ($env:LVCI_COMPARE_POLICY) { $compareNode.policy = $env:LVCI_COMPARE_POLICY }
if ($env:LVCI_COMPARE_MODE)   { $compareNode.mode   = $env:LVCI_COMPARE_MODE }

$index = [ordered]@{
  schema  = 'teststand-compare-session/v1'
  at      = (Get-Date).ToString('o')
  warmup  = $warmupNode
  compare = $compareNode
  outcome = if ($cap) {
    @{ exitCode=[int]$cap.exitCode; seconds=[double]$cap.seconds; command=$cap.command; diff=([bool]($cap.exitCode -eq 1)) }
  } else { $null }
  error   = $err
}
$indexPath = Join-Path $OutputRoot 'session-index.json'
New-Dir $OutputRoot
$index | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $indexPath -Encoding utf8

$exitCode = if ($cap) { [int]$cap.exitCode } else { 1 }
$diffDisplay = if ($index.outcome) { $index.outcome.diff } else { 'unknown' }
$exitDisplay = if ($index.outcome) { $index.outcome.exitCode } else { 'n/a' }
Write-Host ("TestStand Compare Harness result: exit={0} diff={1} capture={2}" -f $exitDisplay, $diffDisplay, $capPath) -ForegroundColor Yellow

exit $exitCode
