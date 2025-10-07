param(
  [ValidateSet('Start','End','Status')][string]$Action = 'End',
  [string]$Reason = 'unspecified',
  [int]$ExpectedSeconds = 90,
  [string]$ResultsDir = 'tests/results',
  [int]$ToleranceSeconds = 5,
  [string]$Id = 'default',
  [switch]$FailOnOutsideMargin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Agent-Wait.ps1')

switch ($Action) {
  'Start' {
    $marker = Start-AgentWait -Reason $Reason -ExpectedSeconds $ExpectedSeconds -ResultsDir $ResultsDir -ToleranceSeconds $ToleranceSeconds -Id $Id
    Write-Host ("Started wait marker: {0}" -f $marker)
    break
  }
  'End' {
    $res = End-AgentWait -ResultsDir $ResultsDir -ToleranceSeconds $ToleranceSeconds -Id $Id
    if ($null -eq $res) { exit 0 }
    $ok = $true
    if ($FailOnOutsideMargin.IsPresent -and -not [bool]$res.withinMargin) { $ok = $false }
    # Emit machine-friendly line
    Write-Output ("RESULT reason={0} elapsed={1}s expected={2}s tol={3}s diff={4}s within={5}" -f $res.reason,$res.elapsedSeconds,$res.expectedSeconds,$res.toleranceSeconds,$res.differenceSeconds,$res.withinMargin)
    if (-not $ok) { exit 2 } else { exit 0 }
  }
  'Status' {
    $outDir = Join-Path $ResultsDir '_agent'
    $sessionDir = Join-Path $outDir (Join-Path 'sessions' $Id)
    $markerPath = Join-Path $sessionDir 'wait-marker.json'
    $lastPath = Join-Path $sessionDir 'wait-last.json'
    if (Test-Path $lastPath) {
      $last = Get-Content $lastPath -Raw | ConvertFrom-Json
      Write-Output ("LAST reason={0} elapsed={1}s expected={2}s tol={3}s diff={4}s within={5}" -f $last.reason,$last.elapsedSeconds,$last.expectedSeconds,$last.toleranceSeconds,$last.differenceSeconds,$last.withinMargin)
    } elseif (Test-Path $markerPath) {
      $m = Get-Content $markerPath -Raw | ConvertFrom-Json
      Write-Output ("MARKER reason={0} expected={1}s tol={2}s started={3}" -f $m.reason,$m.expectedSeconds,$m.toleranceSeconds,$m.startedUtc)
    } else {
      Write-Host '::notice::No wait marker or last result found.'
    }
    break
  }
}
