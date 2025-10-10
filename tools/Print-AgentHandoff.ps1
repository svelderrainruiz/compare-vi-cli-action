[CmdletBinding()]
param(
  [switch]$ApplyToggles,
  [switch]$OpenDashboard,
  [switch]$AutoTrim,
  [string]$Group = 'pester-selfhosted',
  [string]$ResultsRoot = (Join-Path (Resolve-Path '.').Path 'tests/results')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Format-NullableValue {
  param($Value)
  if ($null -eq $Value) { return 'n/a' }
  if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return 'n/a' }
  return $Value
}

function Format-BoolLabel {
  param([object]$Value)
  if ($Value -eq $true) { return 'true' }
  if ($Value -eq $false) { return 'false' }
  return 'unknown'
}

function Write-WatcherStatusSummary {
  param([string]$ResultsRoot)

  $repoRoot = (Resolve-Path '.').Path
  $watcherCli = Join-Path $repoRoot 'tools/Dev-WatcherManager.ps1'
  if (-not (Test-Path -LiteralPath $watcherCli)) {
    Write-Warning "Dev-WatcherManager.ps1 not found: $watcherCli"
    return
  }

  try {
    $statusJson = & pwsh -NoLogo -NoProfile -File $watcherCli -Status -ResultsDir $ResultsRoot
  } catch {
    Write-Warning ("Failed to gather watcher status: {0}" -f $_.Exception.Message)
    return
  }

  if (-not $statusJson) {
    Write-Warning 'Watcher status command returned no output.'
    return
  }

  try {
    $status = $statusJson | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Write-Warning ("Watcher status parse failed: {0}" -f $_.Exception.Message)
    return
  }

  $autoTrimRequested = ($PSBoundParameters.ContainsKey('AutoTrim') -and $AutoTrim) -or ($env:HANDOFF_AUTOTRIM -and ($env:HANDOFF_AUTOTRIM -match '^(1|true|yes)$'))
  $autoTrimExecuted = $false

  Write-Host ''
  Write-Host '[Watcher Status]' -ForegroundColor Cyan
  Write-Host ("  resultsDir      : {0}" -f (Format-NullableValue $ResultsRoot))
  Write-Host ("  state           : {0}" -f (Format-NullableValue $status.state))
  Write-Host ("  alive           : {0}" -f (Format-BoolLabel $status.alive))
  Write-Host ("  verifiedProcess : {0}" -f (Format-BoolLabel $status.verifiedProcess))
  if ($status.verificationReason) {
    Write-Host ("    reason        : {0}" -f $status.verificationReason)
  }
  Write-Host ("  heartbeatFresh  : {0}" -f (Format-BoolLabel $status.heartbeatFresh))
  if ($status.heartbeatReason) {
    Write-Host ("    reason        : {0}" -f $status.heartbeatReason)
  }
  Write-Host ("  lastHeartbeatAt : {0}" -f (Format-NullableValue $status.lastHeartbeatAt))
  $heartbeatAgeLabel = if ($null -ne $status.heartbeatAgeSeconds) { $status.heartbeatAgeSeconds } else { 'n/a' }
  Write-Host ("  heartbeatAgeSec : {0}" -f $heartbeatAgeLabel)
  Write-Host ("  lastActivityAt  : {0}" -f (Format-NullableValue $status.lastActivityAt))
  Write-Host ("  lastProgressAt  : {0}" -f (Format-NullableValue $status.lastProgressAt))
  Write-Host ("  needsTrim       : {0}" -f (Format-BoolLabel $status.needsTrim))
  if ($status.needsTrim) {
    Write-Host '    hint          : npm run dev:watcher:trim' -ForegroundColor Yellow
    if ($status.files -and $status.files.out -and $status.files.out.path) {
      Write-Host ("    out           : {0}" -f $status.files.out.path)
    }
    if ($status.files -and $status.files.err -and $status.files.err.path) {
      Write-Host ("    err           : {0}" -f $status.files.err.path)
    }
  }

  if ($status.needsTrim -and $autoTrimRequested) {
    try {
      & pwsh -NoLogo -NoProfile -File $watcherCli -Trim -ResultsDir $ResultsRoot | Out-Null
      $autoTrimExecuted = $true
      Write-Host '  auto-trim       : executed' -ForegroundColor Green
    } catch {
      Write-Warning ("Auto-trim failed: {0}" -f $_.Exception.Message)
    }
  }

  # Emit a compact JSON telemetry object for automation consumers and write step summary if available
  $telemetry = [ordered]@{
    schema = 'agent-handoff/watcher-telemetry-v1'
    timestamp = (Get-Date).ToString('o')
    resultsDir = $ResultsRoot
    state = $status.state
    alive = $status.alive
    verifiedProcess = $status.verifiedProcess
    heartbeatFresh = $status.heartbeatFresh
    heartbeatReason = $status.heartbeatReason
    lastHeartbeatAt = $status.lastHeartbeatAt
    heartbeatAgeSeconds = $status.heartbeatAgeSeconds
    needsTrim = $status.needsTrim
    autoTrimExecuted = $autoTrimExecuted
    outPath = if ($status.files -and $status.files.out) { $status.files.out.path } else { $null }
    errPath = if ($status.files -and $status.files.err) { $status.files.err.path } else { $null }
  }
  $telemetryJson = ($telemetry | ConvertTo-Json -Depth 4)
  Write-Host ''
  Write-Host '[Watcher Telemetry JSON]'
  Write-Host $telemetryJson

  try {
    $outDir = Join-Path $ResultsRoot '_agent/handoff'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $telemetryPath = Join-Path $outDir 'watcher-telemetry.json'
    $telemetryJson | Out-File -FilePath $telemetryPath -Encoding utf8
  } catch {}

  if ($env:GITHUB_STEP_SUMMARY) {
    $summaryLines = @()
    $summaryLines += '### Handoff — Watcher Status'
    $summaryLines += "- State: $($status.state)"
    $summaryLines += "- Alive: $(Format-BoolLabel $status.alive)"
    $summaryLines += "- Verified: $(Format-BoolLabel $status.verifiedProcess)"
    $summaryLines += "- Heartbeat Fresh: $(Format-BoolLabel $status.heartbeatFresh)"
    if ($status.heartbeatReason) { $summaryLines += "- Heartbeat Reason: $($status.heartbeatReason)" }
    if ($status.lastHeartbeatAt) { $summaryLines += "- Last Heartbeat: $($status.lastHeartbeatAt) (~$heartbeatAgeLabel s)" }
    $summaryLines += "- Needs Trim: $(Format-BoolLabel $status.needsTrim)"
    $summaryLines += if ($autoTrimExecuted) { '- Auto-Trim: executed' } else { '- Auto-Trim: not executed' }
    ($summaryLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  }
}

$handoff = Join-Path (Resolve-Path '.').Path 'AGENT_HANDOFF.txt'
if (-not (Test-Path -LiteralPath $handoff)) { throw "Handoff file not found: $handoff" }

if ($ApplyToggles) {
  $env:LV_SUPPRESS_UI = '1'
  $env:LV_NO_ACTIVATE = '1'
  $env:LV_CURSOR_RESTORE = '1'
  $env:LV_IDLE_WAIT_SECONDS = '2'
  $env:LV_IDLE_MAX_WAIT_SECONDS = '5'
  if (-not $env:WATCH_RESULTS_DIR) {
    $env:WATCH_RESULTS_DIR = Join-Path (Resolve-Path '.').Path 'tests/results/_watch'
  }
}

Get-Content -LiteralPath $handoff
Write-WatcherStatusSummary -ResultsRoot $ResultsRoot

if ($OpenDashboard) {
  $cli = Join-Path (Resolve-Path '.').Path 'tools/Dev-Dashboard.ps1'
  if (Test-Path -LiteralPath $cli) {
    & $cli -Group $Group -ResultsRoot $ResultsRoot -Html -Json | Out-Null
    Write-Host "Dashboard generated under: $ResultsRoot" -ForegroundColor Cyan
  } else {
    Write-Warning "Dev-Dashboard.ps1 not found at: $cli"
  }
}
