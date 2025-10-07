param([switch]$Quiet)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$path = Join-Path (Get-Location) 'AGENT_HANDOFF.txt'
if (-not (Test-Path -LiteralPath $path)) { Write-Error "AGENT_HANDOFF.txt not found at $path"; exit 2 }
$text = Get-Content -LiteralPath $path -Raw
if (-not $Quiet) {
  Write-Host '=== Agent Handoff (from AGENT_HANDOFF.txt) ==='
  Write-Host $text
  Write-Host ''
  Write-Host 'Next suggested commands:'
  Write-Host '  # Safe local toggles'
  Write-Host "  `$env:LV_SUPPRESS_UI='1'; `$env:LV_NO_ACTIVATE='1'; `$env:LV_CURSOR_RESTORE='1'; `$env:LV_IDLE_WAIT_SECONDS='2'; `$env:LV_IDLE_MAX_WAIT_SECONDS='5'"
  Write-Host '  # Quick rogue scan'
  Write-Host "  pwsh -File tools/Detect-RogueLV.ps1 -ResultsDir tests/results -LookBackSeconds 900 -AppendToStepSummary"
  Write-Host '  # PID tracking test (Integration)'
  Write-Host "  Import-Module Pester; `$c=New-PesterConfiguration; `$c.Run.Path='tests/CompareVI.PIDTracking.Tests.ps1'; `$c.Output.Verbosity='Normal'; Invoke-Pester -Configuration `$c"
}
Write-Output $text
