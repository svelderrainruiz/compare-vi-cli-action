#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$BaseVi,
  [Parameter(Mandatory)][string]$HeadVi,
  [ValidateSet('normal','cli-suppressed','git-context','duplicate-window')]
  [string]$Mode = 'normal',
  [int]$SentinelTtlSeconds = 60,
  [switch]$RenderReport,
  [switch]$UseStub,
  [switch]$ProbeSetup,
  [string]$ResultsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  try { return (git -C (Get-Location).Path rev-parse --show-toplevel 2>$null).Trim() } catch { return (Get-Location).Path }
}

$repoRoot = Resolve-RepoRoot
if (-not $repoRoot) { throw 'Unable to determine repository root.' }

$driverPath = Join-Path $repoRoot 'tools' 'Invoke-LVCompare.ps1'
if (-not (Test-Path -LiteralPath $driverPath -PathType Leaf)) {
  throw "Invoke-LVCompare.ps1 not found at $driverPath"
}

if (-not (Test-Path -LiteralPath $BaseVi -PathType Leaf)) { throw "Base VI not found: $BaseVi" }
if (-not (Test-Path -LiteralPath $HeadVi -PathType Leaf)) { throw "Head VI not found: $HeadVi" }

if ($ProbeSetup.IsPresent -and -not $UseStub.IsPresent) {
  $setupScript = Join-Path $repoRoot 'tools' 'Verify-LVCompareSetup.ps1'
  if (Test-Path -LiteralPath $setupScript -PathType Leaf) {
    try { & $setupScript -ProbeCli -Search | Out-Null } catch { throw "LVCompare setup probe failed: $($_.Exception.Message)" }
  }
}

$timestamp = (Get-Date -Format 'yyyyMMddTHHmmss')
$resultsRootResolved = if ($ResultsRoot) {
  if ([System.IO.Path]::IsPathRooted($ResultsRoot)) { $ResultsRoot } else { Join-Path $repoRoot $ResultsRoot }
} else {
  Join-Path $repoRoot (Join-Path 'tests/results/_agent/local-diff' $timestamp)
}
if (Test-Path -LiteralPath $resultsRootResolved) { Remove-Item -LiteralPath $resultsRootResolved -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $resultsRootResolved -Force | Out-Null

function Invoke-CompareRun {
  param(
    [Parameter(Mandatory)][string]$RunDir,
    [string]$Mode,
    [switch]$RenderReport,
    [switch]$UseStub
  )

  New-Item -ItemType Directory -Path $RunDir -Force | Out-Null

  $prev = @{
    COMPAREVI_NO_CLI_CAPTURE   = $env:COMPAREVI_NO_CLI_CAPTURE
    COMPAREVI_SUPPRESS_CLI_IN_GIT = $env:COMPAREVI_SUPPRESS_CLI_IN_GIT
    COMPAREVI_WARN_CLI_IN_GIT  = $env:COMPAREVI_WARN_CLI_IN_GIT
    COMPAREVI_CLI_SENTINEL_TTL = $env:COMPAREVI_CLI_SENTINEL_TTL
    GIT_DIR = $env:GIT_DIR
    GIT_PREFIX = $env:GIT_PREFIX
  }

  try {
    switch ($Mode) {
      'cli-suppressed' { $env:COMPAREVI_NO_CLI_CAPTURE = '1' }
      'git-context'    { $env:COMPAREVI_SUPPRESS_CLI_IN_GIT = '1'; $env:COMPAREVI_WARN_CLI_IN_GIT = '1'; if (-not $env:GIT_DIR) { $env:GIT_DIR = '.' } }
      default { }
    }

    $params = @{
      BaseVi    = (Resolve-Path -LiteralPath $BaseVi).Path
      HeadVi    = (Resolve-Path -LiteralPath $HeadVi).Path
      OutputDir = $RunDir
      Quiet     = $true
    }
    if ($RenderReport.IsPresent) { $params.RenderReport = $true }
    if ($UseStub.IsPresent) {
      $stubPath = Join-Path $repoRoot 'tests' 'stubs' 'Invoke-LVCompare.stub.ps1'
      if (-not (Test-Path -LiteralPath $stubPath -PathType Leaf)) { throw "Stub not found at $stubPath" }
      $params.CaptureScriptPath = $stubPath
    }

    & $driverPath @params *> $null

    $capPath = Join-Path $RunDir 'lvcompare-capture.json'
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw "Capture JSON not found at $capPath" }
    $cap = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json -Depth 8

    $envCli = $null
    if ($cap -and $cap.PSObject.Properties['environment'] -and $cap.environment -and $cap.environment.PSObject.Properties['cli']) {
      $envCli = $cap.environment.cli
    }

    return [pscustomobject]@{
      outputDir  = $RunDir
      capture    = $capPath
      exitCode   = $cap.exitCode
      seconds    = $cap.seconds
      cliSkipped = if ($envCli -and $envCli.PSObject.Properties['skipped']) { [bool]$envCli.skipped } else { $false }
      skipReason = if ($envCli -and $envCli.PSObject.Properties['skipReason']) { [string]$envCli.skipReason } else { $null }
    }
  } finally {
    foreach ($k in $prev.Keys) {
      $v = $prev[$k]
      if ($null -eq $v) { Remove-Item -ErrorAction SilentlyContinue -LiteralPath "Env:$k" } else { [Environment]::SetEnvironmentVariable($k, $v, 'Process') }
    }
  }
}

$summary = [ordered]@{
  schema     = 'local-diff-session@v1'
  mode       = $Mode
  base       = (Resolve-Path -LiteralPath $BaseVi).Path
  head       = (Resolve-Path -LiteralPath $HeadVi).Path
  resultsDir = $resultsRootResolved
  runs       = @()
}

# Run 1 (always)
$run1Dir = Join-Path $resultsRootResolved 'run-01'
$r1 = Invoke-CompareRun -RunDir $run1Dir -Mode $Mode -RenderReport:$RenderReport -UseStub:$UseStub
$summary.runs += $r1

if ($Mode -eq 'duplicate-window') {
  $prevTtl = $env:COMPAREVI_CLI_SENTINEL_TTL
  try {
    $env:COMPAREVI_CLI_SENTINEL_TTL = [string][Math]::Max(1, $SentinelTtlSeconds)
    $run2Dir = Join-Path $resultsRootResolved 'run-02'
    $r2 = Invoke-CompareRun -RunDir $run2Dir -Mode 'normal' -RenderReport:$RenderReport -UseStub:$UseStub
    $summary.runs += $r2
  } finally {
    if ($null -eq $prevTtl) { Remove-Item Env:COMPAREVI_CLI_SENTINEL_TTL -ErrorAction SilentlyContinue } else { $env:COMPAREVI_CLI_SENTINEL_TTL = $prevTtl }
  }
}

$summaryPath = Join-Path $resultsRootResolved 'local-diff-summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

Write-Host ''
Write-Host '=== Local Diff Session Summary ===' -ForegroundColor Cyan
Write-Host ("Mode     : {0}" -f $summary.mode)
Write-Host ("Base     : {0}" -f $summary.base)
Write-Host ("Head     : {0}" -f $summary.head)
Write-Host ("Results  : {0}" -f $summary.resultsDir)
for ($i = 0; $i -lt $summary.runs.Count; $i++) {
  $r = $summary.runs[$i]
  Write-Host ("Run {0}: exit={1}, skipped={2}, reason={3}, outDir={4}" -f ($i+1), $r.exitCode, ([bool]$r.cliSkipped), ($r.skipReason ?? '-'), $r.outputDir)
}

return [pscustomobject]@{
  resultsDir = $resultsRootResolved
  summary    = $summaryPath
  runs       = @($summary.runs)
}

