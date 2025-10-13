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

function Write-HookSummaries {
  param([string]$ResultsRoot)

  $hooksDir = Join-Path $ResultsRoot '_hooks'
  Write-Host ''
  Write-Host '[Hook Summaries]' -ForegroundColor Cyan
  if (-not (Test-Path -LiteralPath $hooksDir -PathType Container)) {
    Write-Host '  (no hook summaries found)'
    return @()
  }

  $files = Get-ChildItem -LiteralPath $hooksDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  if (-not $files) {
    Write-Host '  (no hook summaries found)'
    return @()
  }

  $latest = @{}
  foreach ($file in $files) {
    try {
      $summary = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
      continue
    }
    if (-not $summary) { continue }
    $hookName = if ($summary.PSObject.Properties['hook']) { $summary.hook } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
    if (-not $hookName) { continue }
    if (-not $latest.ContainsKey($hookName)) {
      $latest[$hookName] = [ordered]@{
        hook = $hookName
        file = $file.FullName
        status = $summary.status
        exitCode = $summary.exitCode
        timestamp = $summary.timestamp
        plane = if ($summary.environment) { $summary.environment.plane } else { $null }
        enforcement = if ($summary.environment) { $summary.environment.enforcement } else { $null }
      }
    }
  }

  if ($latest.Count -eq 0) {
    Write-Host '  (no hook summaries found)'
    return @()
  }

  foreach ($entry in ($latest.Keys | Sort-Object)) {
    $info = $latest[$entry]
    Write-Host ("  hook        : {0}" -f $info.hook)
    Write-Host ("    status    : {0}" -f (Format-NullableValue $info.status))
    Write-Host ("    exitCode  : {0}" -f (Format-NullableValue $info.exitCode))
    Write-Host ("    plane     : {0}" -f (Format-NullableValue $info.plane))
    Write-Host ("    enforce   : {0}" -f (Format-NullableValue $info.enforcement))
    Write-Host ("    timestamp : {0}" -f (Format-NullableValue $info.timestamp))
    Write-Host ("    file      : {0}" -f $info.file)
  }

  return ($latest.Values | Sort-Object hook)
}

function Write-WatcherStatusSummary {
  param(
    [string]$ResultsRoot,
    [switch]$RequestAutoTrim
  )

  $repoRoot = (Resolve-Path '.').Path
  $watcherCli = Join-Path $repoRoot 'tools/Dev-WatcherManager.ps1'
  if (-not (Test-Path -LiteralPath $watcherCli)) {
    Write-Warning "Dev-WatcherManager.ps1 not found: $watcherCli"
    return
  }

  try {
    # Prefer in-process invocation to avoid nested pwsh; capture information stream just in case
    $statusJson = & $watcherCli -Status -ResultsDir $ResultsRoot 6>&1
    if (-not $statusJson) {
      # Fallback to spawning pwsh to capture host output if needed
      $statusJson = & pwsh -NoLogo -NoProfile -File $watcherCli -Status -ResultsDir $ResultsRoot
    }
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

  $autoTrimRequested = $RequestAutoTrim.IsPresent -or ($env:HANDOFF_AUTOTRIM -and ($env:HANDOFF_AUTOTRIM -match '^(1|true|yes)$'))
  $autoTrimExecuted = $false
  $autoTrimOutput = @()

  if ($autoTrimRequested) {
    $shouldTrim = $true
    if ($status) {
      if ($status.PSObject.Properties['needsTrim']) {
        $shouldTrim = [bool]$status.needsTrim
      } elseif ($status.PSObject.Properties['autoTrim'] -and $status.autoTrim) {
        # If eligibility is known, honor it
        if ($status.autoTrim.PSObject.Properties['eligible']) {
          $shouldTrim = [bool]$status.autoTrim.eligible
        }
      }
    }
    if ($shouldTrim) {
      try {
        # Capture both success and information streams
        $autoTrimOutput = & $watcherCli -AutoTrim -ResultsDir $ResultsRoot 6>&1
        if ($autoTrimOutput -match 'Trimmed watcher logs') { $autoTrimExecuted = $true }
      } catch {
        Write-Warning ("Auto-trim failed: {0}" -f $_.Exception.Message)
      }
      try {
        $statusJson = & $watcherCli -Status -ResultsDir $ResultsRoot 6>&1
        if (-not $statusJson) {
          $statusJson = & pwsh -NoLogo -NoProfile -File $watcherCli -Status -ResultsDir $ResultsRoot
        }
        if ($statusJson) { $status = $statusJson | ConvertFrom-Json -ErrorAction Stop }
      } catch {
        Write-Warning ("Failed to refresh watcher status after auto-trim: {0}" -f $_.Exception.Message)
      }
    } else {
      $autoTrimExecuted = $false
      $autoTrimOutput = @('Auto-trim skipped (not needed).')
    }
  }

  $autoTrim = $null
  if ($status -and $status.PSObject.Properties['autoTrim']) {
    $autoTrim = $status.autoTrim
  }

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
  if ($status.files -and $status.files.status) {
    $statusExists = if ($status.files.status.exists) { 'present' } else { 'missing' }
    Write-Host ("  status.json     : {0}" -f $statusExists)
  }
  if ($status.files -and $status.files.heartbeat) {
    $hbExists = if ($status.files.heartbeat.exists) { 'present' } else { 'missing' }
    Write-Host ("  heartbeat.json  : {0}" -f $hbExists)
  }
  if ($autoTrim) {
    Write-Host ("  autoTrim.eligible           : {0}" -f (Format-BoolLabel $autoTrim.eligible))
    Write-Host ("  autoTrim.cooldownSeconds    : {0}" -f (Format-NullableValue $autoTrim.cooldownSeconds))
    Write-Host ("  autoTrim.cooldownRemaining  : {0}" -f (Format-NullableValue $autoTrim.cooldownRemainingSeconds))
    Write-Host ("  autoTrim.nextEligibleAt     : {0}" -f (Format-NullableValue $autoTrim.nextEligibleAt))
    Write-Host ("  autoTrim.lastTrimAt         : {0}" -f (Format-NullableValue $autoTrim.lastTrimAt))
    Write-Host ("  autoTrim.lastTrimKind       : {0}" -f (Format-NullableValue $autoTrim.lastTrimKind))
    Write-Host ("  autoTrim.lastTrimBytes      : {0}" -f (Format-NullableValue $autoTrim.lastTrimBytes))
    Write-Host ("  autoTrim.trimCount          : {0}" -f (Format-NullableValue $autoTrim.trimCount))
    Write-Host ("  autoTrim.autoTrimCount      : {0}" -f (Format-NullableValue $autoTrim.autoTrimCount))
    Write-Host ("  autoTrim.manualTrimCount    : {0}" -f (Format-NullableValue $autoTrim.manualTrimCount))
  }
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

  if ($autoTrimRequested) {
    $autoTrimStatusLabel = if ($autoTrimExecuted) { 'executed' } else { 'not executed' }
    Write-Host ("  auto-trim       : {0}" -f $autoTrimStatusLabel)
    # Normalize output records (InformationRecord vs string) and print non-empty lines
    $lines = @()
    foreach ($rec in $autoTrimOutput) {
      if ($null -eq $rec) { continue }
      if ($rec -is [System.Management.Automation.InformationRecord]) {
        $lines += [string]$rec.MessageData
      } else {
        $lines += [string]$rec
      }
    }
    foreach ($line in ($lines | Where-Object { $_ -and $_.Trim().Length -gt 0 })) {
      Write-Host ("    > {0}" -f $line.Trim())
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
    autoTrim = if ($autoTrim) {
      [ordered]@{
        eligible = $autoTrim.eligible
        cooldownSeconds = $autoTrim.cooldownSeconds
        cooldownRemainingSeconds = $autoTrim.cooldownRemainingSeconds
        nextEligibleAt = $autoTrim.nextEligibleAt
        lastTrimAt = $autoTrim.lastTrimAt
        lastTrimKind = $autoTrim.lastTrimKind
        lastTrimBytes = $autoTrim.lastTrimBytes
        trimCount = $autoTrim.trimCount
        autoTrimCount = $autoTrim.autoTrimCount
        manualTrimCount = $autoTrim.manualTrimCount
      }
    } else {
      $null
    }
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
    if ($autoTrim) {
      $summaryLines += "- Auto-Trim Eligible: $(Format-BoolLabel $autoTrim.eligible)"
      if ($autoTrim.cooldownRemainingSeconds) {
        $summaryLines += "- Auto-Trim Cooldown Remaining: $(Format-NullableValue $autoTrim.cooldownRemainingSeconds)s"
      }
      if ($autoTrim.nextEligibleAt) {
        $summaryLines += "- Auto-Trim Next Eligible: $(Format-NullableValue $autoTrim.nextEligibleAt)"
      }
      if ($autoTrim.lastTrimAt) {
        $summaryLines += "- Auto-Trim Last Trim: $(Format-NullableValue $autoTrim.lastTrimAt) ($((Format-NullableValue $autoTrim.lastTrimKind)))"
      }
    }
    $summaryLines += "- Needs Trim: $(Format-BoolLabel $status.needsTrim)"
    if ($autoTrimRequested) {
      $summaryLines += if ($autoTrimExecuted) { '- Auto-Trim: executed' } else { '- Auto-Trim: not executed' }
    }
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

try {
  $repoRoot = (Resolve-Path '.').Path
  $priorityScript = Join-Path $repoRoot 'tools' 'priority' 'sync-standing-priority.mjs'
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCmd -and (Test-Path -LiteralPath $priorityScript -PathType Leaf)) {
    & $nodeCmd.Source $priorityScript | Out-Host
  } else {
    Write-Host '::notice::Standing priority sync skipped (node or script missing).'
  }
} catch {
  Write-Warning ("Standing priority sync failed: {0}" -f $_.Exception.Message)
}

try {
  $issueDir = Join-Path (Resolve-Path '.').Path 'tests/results/_agent/issue'
  if (Test-Path -LiteralPath $issueDir -PathType Container) {
    $latestIssue = Get-ChildItem -LiteralPath $issueDir -Filter '*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestIssue) {
      $issueSnap = Get-Content -LiteralPath $latestIssue.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
      Write-Host ''
      Write-Host '[Standing Priority]' -ForegroundColor Cyan
      Write-Host ("  issue    : #{0}" -f $issueSnap.number)
      Write-Host ("  title    : {0}" -f (Format-NullableValue $issueSnap.title))
      Write-Host ("  state    : {0}" -f (Format-NullableValue $issueSnap.state))
      Write-Host ("  updated  : {0}" -f (Format-NullableValue $issueSnap.updatedAt))
      Write-Host ("  digest   : {0}" -f (Format-NullableValue $issueSnap.digest))

      if ($env:GITHUB_STEP_SUMMARY) {
        $priorityLines = @(
          '### Standing Priority',
          '',
          ('- Issue: #{0} — {1}' -f $issueSnap.number, (Format-NullableValue $issueSnap.title)),
          ('- State: {0}  Updated: {1}' -f (Format-NullableValue $issueSnap.state), (Format-NullableValue $issueSnap.updatedAt)),
          ('- Digest: `{0}`' -f (Format-NullableValue $issueSnap.digest))
        )
        ($priorityLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
      }

      $handoffDir = Join-Path $ResultsRoot '_agent/handoff'
      New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null
      Copy-Item -LiteralPath $latestIssue.FullName -Destination (Join-Path $handoffDir 'issue-summary.json') -Force
      $routerSrc = Join-Path $issueDir 'router.json'
      if (Test-Path -LiteralPath $routerSrc -PathType Leaf) {
        Copy-Item -LiteralPath $routerSrc -Destination (Join-Path $handoffDir 'issue-router.json') -Force
      }
    }
  }
} catch {
  Write-Warning ("Failed to display standing priority summary: {0}" -f $_.Exception.Message)
}

try {
  $releasePath = Join-Path (Resolve-Path '.').Path 'tests/results/_agent/handoff/release-summary.json'
  if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
    $release = Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Host ''
    Write-Host '[SemVer Status]' -ForegroundColor Cyan
    Write-Host ("  version : {0}" -f (Format-NullableValue $release.version))
    Write-Host ("  valid   : {0}" -f (Format-BoolLabel $release.valid))
    if ($release.issues) {
      foreach ($issue in $release.issues) {
        Write-Host ("    issue : {0}" -f $issue)
      }
    }
    $handoffDir = Join-Path $ResultsRoot '_agent/handoff'
    New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null
    Copy-Item -LiteralPath $releasePath -Destination (Join-Path $handoffDir 'release-summary.json') -Force
    if ($env:GITHUB_STEP_SUMMARY) {
      $releaseLines = @(
        '### SemVer Status',
        '',
        ('- Version: {0}' -f (Format-NullableValue $release.version)),
        ('- Valid: {0}' -f (Format-BoolLabel $release.valid))
      )
      if ($release.issues -and $release.issues.Count -gt 0) {
        foreach ($issue in $release.issues) {
          $releaseLines += ('  - {0}' -f $issue)
        }
      }
      ($releaseLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }
  }
} catch {
  Write-Warning ("Failed to load SemVer summary: {0}" -f $_.Exception.Message)
}

Write-WatcherStatusSummary -ResultsRoot $ResultsRoot -RequestAutoTrim:$AutoTrim

$hookSummaries = Write-HookSummaries -ResultsRoot $ResultsRoot
if ($hookSummaries -and $hookSummaries.Count -gt 0) {
  if ($env:GITHUB_STEP_SUMMARY) {
    $hookSummaryLines = @('### Hook Summaries','','| hook | status | plane | enforcement | exit | timestamp |','| --- | --- | --- | --- | --- | --- |')
    foreach ($hook in $hookSummaries) {
      $hookSummaryLines += ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $hook.hook, (Format-NullableValue $hook.status), (Format-NullableValue $hook.plane), (Format-NullableValue $hook.enforcement), (Format-NullableValue $hook.exitCode), (Format-NullableValue $hook.timestamp))
    }
    ($hookSummaryLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  }

  $handoffDir = Join-Path $ResultsRoot '_agent/handoff'
  New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null
  ($hookSummaries | ConvertTo-Json -Depth 4) | Out-File -FilePath (Join-Path $handoffDir 'hook-summary.json') -Encoding utf8
}

if ($OpenDashboard) {
  $cli = Join-Path (Resolve-Path '.').Path 'tools/Dev-Dashboard.ps1'
  if (Test-Path -LiteralPath $cli) {
    & $cli -Group $Group -ResultsRoot $ResultsRoot -Html -Json | Out-Null
    Write-Host "Dashboard generated under: $ResultsRoot" -ForegroundColor Cyan
  } else {
    Write-Warning "Dev-Dashboard.ps1 not found at: $cli"
  }
}
