#Requires -Version 7.0
[CmdletBinding()]
param(
  [switch]$Execute,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Npm {
  param([string]$Script)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'npm'
  $psi.ArgumentList.Add('run')
  $psi.ArgumentList.Add($Script)
  $psi.WorkingDirectory = (Resolve-Path '.').Path
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if ($stdout) { Write-Host $stdout.TrimEnd() }
  if ($stderr) { Write-Warning $stderr.TrimEnd() }
  if ($proc.ExitCode -ne 0) {
    throw "npm run $Script exited with code $($proc.ExitCode)"
  }
}

Write-Host '[release] Refreshing standing priority snapshot…'
Invoke-Npm -Script 'priority:sync'

$routerPath = Join-Path (Resolve-Path '.').Path 'tests/results/_agent/issue/router.json'
if (-not (Test-Path -LiteralPath $routerPath -PathType Leaf)) {
  throw "Router plan not found at $routerPath. Run priority:sync first."
}

$router = Get-Content -LiteralPath $routerPath -Raw | ConvertFrom-Json -ErrorAction Stop
$actions = @($router.actions | Sort-Object priority)

Write-Host '[release] Planned actions:' -ForegroundColor Cyan
foreach ($action in $actions) {
  Write-Host ("  - {0} (priority {1})" -f $action.key, $action.priority)
  if ($action.scripts) {
    foreach ($script in $action.scripts) {
      Write-Host ("      script: {0}" -f $script)
    }
  }
}

$hasRelease = $actions | Where-Object { $_.key -eq 'release:prep' }
if ($hasRelease) {
  Write-Host '[release] Running release preparation scripts…' -ForegroundColor Cyan
  foreach ($script in $hasRelease.scripts) {
    Write-Host ("[release] Executing: {0}" -f $script)
    & pwsh -NoLogo -NoProfile -Command $script
  }
} else {
  Write-Host '[release] No release-specific actions found in router.' -ForegroundColor Yellow
}

if ($Execute -and $hasRelease) {
  Write-Host '[release] Invoking Branch-Orchestrator with execution…' -ForegroundColor Cyan
  & pwsh -NoLogo -NoProfile -File (Join-Path (Resolve-Path '.').Path 'tools/Branch-Orchestrator.ps1') -Execute
} elseif (-not $DryRun -and $hasRelease) {
  Write-Host '[release] Running branch orchestrator in dry-run mode (default)…'
  & pwsh -NoLogo -NoProfile -File (Join-Path (Resolve-Path '.').Path 'tools/Branch-Orchestrator.ps1') -DryRun
} else {
  Write-Host '[release] Branch orchestrator skipped.' -ForegroundColor Yellow
}

Write-Host '[release] Simulation complete.'
