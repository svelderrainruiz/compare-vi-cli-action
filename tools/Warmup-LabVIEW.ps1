<#
.SYNOPSIS
  Best-effort LabVIEW warmup for self-hosted Windows runners.

.DESCRIPTION
  Ensures a LabVIEW.exe instance is started before tests/compare work begins by
  briefly launching LVCompare.exe (canonical path) against two VIs, then
terminating LVCompare.exe once LabVIEW has been initialized.

  No-op when LabVIEW is already running or when LVCompare is not present.

.PARAMETER BaseVi
  Optional base VI path. Defaults to repo-root VI1.vi when present.

.PARAMETER HeadVi
  Optional head VI path. Defaults to repo-root VI2.vi when present.

.PARAMETER TimeoutSeconds
  Time to wait for LabVIEW to appear after spawning LVCompare. Default 15.

.PARAMETER KeepLVCompare
  When supplied (or when WARMUP_KEEP_LVCOMPARE=1), leaves LVCompare.exe running after warm-up.
#>
[CmdletBinding()]
param(
  [string]$BaseVi,
  [string]$HeadVi,
  [int]$TimeoutSeconds = 15,
  [switch]$KeepLVCompare,
  [string]$SnapshotPath = 'tests/results/_warmup/labview-processes.json',
  [switch]$SkipSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-StepSummaryLine([string]$line) {
  if ($env:GITHUB_STEP_SUMMARY) { $line | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8 }
}

function Invoke-ProcessSnapshot {
  if ($SkipSnapshot) {
    Write-Host "Warmup: skipping LabVIEW process snapshot (per flag)."
    return
  }
  $captureScript = Join-Path $PSScriptRoot 'Capture-LabVIEWSnapshot.ps1'
  if (-not (Test-Path -LiteralPath $captureScript)) {
    Write-Host "Warmup: snapshot script not found at $captureScript" -ForegroundColor Yellow
    return
  }
  try {
    & $captureScript -OutputPath $SnapshotPath -Quiet
  } catch {
    Write-Host "Warmup: failed to capture LabVIEW process snapshot: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

if ($IsWindows -ne $true) { return }

# If LabVIEW already running, bail out quickly
try {
  $existing = @(Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue)
  if ($existing.Count -gt 0) {
    Write-Host "Warmup: LabVIEW already running (PID(s): $($existing.Id -join ','))"
    Write-StepSummaryLine "- Warmup: LabVIEW already running (PID(s): $($existing.Id -join ','))"
    return
  }
} catch {}

$repoRoot = (Get-Location).Path
if (-not $BaseVi) { $BaseVi = Join-Path $repoRoot 'VI1.vi' }
if (-not $HeadVi) { $HeadVi = Join-Path $repoRoot 'VI2.vi' }

$cli = 'C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe'
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
  Write-Host "Warmup: LVCompare not found at canonical path; skipping." -ForegroundColor Yellow
  Write-StepSummaryLine "- Warmup: LVCompare.exe not found; skipped"
  return
}

if (-not (Test-Path -LiteralPath $BaseVi)) { Write-Host "Warmup: Base VI not found: $BaseVi" -ForegroundColor Yellow; return }
if (-not (Test-Path -LiteralPath $HeadVi)) { Write-Host "Warmup: Head VI not found: $HeadVi" -ForegroundColor Yellow; return }

if ($env:WARMUP_MODE -eq 'preflight' -or $env:WARMUP_SKIP_ARGS -eq '1') {
  Write-Host "Warmup: starting LVCompare without VI args (preflight)."
  Write-StepSummaryLine "- Warmup: LVCompare preflight (no args)"
  $p = Start-Process -FilePath $cli -PassThru
}
else {
  Write-Host "Warmup: starting LVCompare to spawn LabVIEW."
  Write-StepSummaryLine "- Warmup: starting LVCompare to spawn LabVIEW"
  # Start LVCompare normally (UI allowed). Do not suppress UI; do not redirect.
  $p = Start-Process -FilePath $cli -ArgumentList @($BaseVi,$HeadVi) -PassThru
}

# Poll for LabVIEW to appear
$deadline = (Get-Date).AddSeconds([Math]::Max(1,$TimeoutSeconds))
do {
  Start-Sleep -Milliseconds 200
  try { $lv = @(Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue) } catch { $lv = @() }
  if ($lv.Count -gt 0) { break }
} while ((Get-Date) -lt $deadline)

if ($lv.Count -gt 0) {
  Write-Host "Warmup: LabVIEW started (PID(s): $($lv.Id -join ','))"
  Write-StepSummaryLine "- Warmup: LabVIEW started (PID(s): $($lv.Id -join ','))"
} else {
  Write-Host "Warmup: LabVIEW did not start within timeout ($TimeoutSeconds s)." -ForegroundColor Yellow
  Write-StepSummaryLine "- Warmup: LabVIEW did not start within timeout ($TimeoutSeconds s)"
}

$shouldKeep = $KeepLVCompare.IsPresent -or ($env:WARMUP_KEEP_LVCOMPARE -eq '1')
if ($shouldKeep) {
  Write-Host "Warmup: leaving LVCompare running (KeepLVCompare requested)."
  Write-StepSummaryLine "- Warmup: LVCompare left running (Keep flag)"
  Invoke-ProcessSnapshot
  return
}

if ($p -and -not $p.HasExited) {
  Write-Host "Warmup: stopping LVCompare (PID=$($p.Id))."
  try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {
    Write-Host "Warmup: failed to stop LVCompare by PID ($($p.Id)): $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

try {
  $remainingLvCompare = @(Get-Process -Name 'LVCompare' -ErrorAction SilentlyContinue)
  if ($remainingLvCompare.Count -gt 0) {
    foreach ($proc in $remainingLvCompare) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
    }
    $remainingLvCompare = @(Get-Process -Name 'LVCompare' -ErrorAction SilentlyContinue)
  }
  if ($remainingLvCompare.Count -eq 0) {
    Write-Host "Warmup: LVCompare stopped; only LabVIEW remains."
    Write-StepSummaryLine "- Warmup: LVCompare stopped after warm-up"
  } else {
    Write-Host "Warmup: LVCompare still running after stop attempt (PID(s): $($remainingLvCompare.Id -join ','))" -ForegroundColor Yellow
    Write-StepSummaryLine "- Warmup: LVCompare still running after stop attempt (PID(s): $($remainingLvCompare.Id -join ','))"
  }
} catch {
  Write-Host "Warmup: error while checking LVCompare state: $($_.Exception.Message)" -ForegroundColor Yellow
}

Invoke-ProcessSnapshot
