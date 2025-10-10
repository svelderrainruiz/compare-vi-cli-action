param(
  [switch]$Ensure,
  [switch]$Stop,
  [switch]$Status,
  [switch]$Trim,
  [switch]$AutoTrim,
  [string]$ResultsDir = 'tests/results',
  [int]$WarnSeconds = 60,
  [int]$HangSeconds = 120,
  [int]$PollMs = 2000,
  [int]$NoProgressSeconds = 90,
  [string]$ProgressRegex = '^(?:\s*\[[-+\*]\]|\s*It\s)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MaxLogBytes = 5MB
$MaxLogLines = 4000

function Get-WatcherPaths {
  param([string]$ResultsDir)
  $root = [System.IO.Path]::GetFullPath($ResultsDir)
  $agentDir = Join-Path $root '_agent'
  $watchDir = Join-Path $agentDir 'watcher'
  if (-not (Test-Path -LiteralPath $watchDir)) { New-Item -ItemType Directory -Force -Path $watchDir | Out-Null }
  [pscustomobject]@{
    Root     = $root
    Dir      = $watchDir
    PidFile  = Join-Path $watchDir 'pid.json'
    OutFile  = Join-Path $watchDir 'watch.out'
    ErrFile  = Join-Path $watchDir 'watch.err'
    StatusFile = Join-Path $watchDir 'watcher-status.json'
    HeartbeatFile = Join-Path $watchDir 'watcher-self.json'
  }
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Test-ProcessAlive {
  param([int]$Pid)
  try { $p = Get-Process -Id $Pid -ErrorAction Stop; return ($p -ne $null) } catch { return $false }
}

function Get-ProcessCommandLine {
  param([int]$Pid)
  try {
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$Pid" -ErrorAction Stop
    return $cim.CommandLine
  } catch {
    return $null
  }
}

function Get-WatcherProcessInfo {
  param([int]$Pid)
  try {
    $proc = Get-Process -Id $Pid -ErrorAction Stop
  } catch {
    return $null
  }
  $cmdLine = Get-ProcessCommandLine -Pid $Pid
  $path = $null
  try { $path = $proc.MainModule.FileName } catch {}
  [pscustomobject]@{
    Process = $proc
    CommandLine = $cmdLine
    Path = $path
  }
}

function Test-WatcherProcess {
  param(
    [pscustomobject]$ProcessInfo,
    [pscustomobject]$Paths
  )
  if (-not $ProcessInfo) {
    return [pscustomobject]@{ IsValid = $false; Reason = 'process not found' }
  }
  $cmd = $ProcessInfo.CommandLine
  if (-not $cmd) {
    return [pscustomobject]@{ IsValid = $false; Reason = 'command line unavailable' }
  }
  $cmdLower = $cmd.ToLowerInvariant()
  $scriptPath = (Join-Path (Split-Path -Parent $PSCommandPath) 'follow-pester-artifacts.mjs')
  $scriptLower = $scriptPath.ToLowerInvariant()
  $resultsLower = $Paths.Root.ToLowerInvariant()
  if ($cmdLower -notlike "*$scriptLower*") {
    return [pscustomobject]@{ IsValid = $false; Reason = 'unexpected script path' }
  }
  if ($cmdLower -notlike "*$resultsLower*") {
    return [pscustomobject]@{ IsValid = $false; Reason = 'unexpected results directory' }
  }
  [pscustomobject]@{ IsValid = $true; Reason = '' }
}

function Trim-LogFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $info = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $info) { return $false }
  if ($info.Length -le $MaxLogBytes) { return $false }
  $lines = Get-Content -LiteralPath $Path -Tail $MaxLogLines
  $temp = [System.IO.Path]::GetTempFileName()
  try {
    $lines | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $Path -Force
  } catch {
    try { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } catch {}
    throw
  }
  return $true
}

function Get-LogSnapshot {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ path = $Path; exists = $false }
  }
  $item = Get-Item -LiteralPath $Path
  [pscustomobject]@{
    path = $Path
    exists = $true
    sizeBytes = $item.Length
    lastWriteTime = $item.LastWriteTimeUtc.ToString('o')
  }
}

function Get-PropValue {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  try {
    return $Object | Select-Object -ExpandProperty $Name -ErrorAction Stop
  } catch {
    return $null
  }
}

function Start-DevWatcher {
  param([string]$ResultsDir,[int]$WarnSeconds,[int]$HangSeconds,[int]$PollMs,[int]$NoProgressSeconds,[string]$ProgressRegex,[switch]$IncludeProgressRegex)
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  foreach ($logPath in @($paths.OutFile, $paths.ErrFile)) {
    try { Trim-LogFile -Path $logPath | Out-Null } catch { Write-Warning ([string]::Format('[watcher] Failed to trim log {0}: {1}', $logPath, $_.Exception.Message)) }
  }
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { throw 'Node.js not found on PATH (required for watcher).' }
  $script = Join-Path (Split-Path -Parent $PSCommandPath) 'follow-pester-artifacts.mjs'
  if (-not (Test-Path -LiteralPath $script)) { throw "Watcher script not found: $script" }
  $args = @(
    $script,
    '--results', $paths.Root,
    '--warn-seconds', [string]$WarnSeconds,
    '--hang-seconds', [string]$HangSeconds,
    '--poll-ms', [string]$PollMs,
    '--no-progress-seconds', [string]$NoProgressSeconds,
    '--status-file', $paths.StatusFile,
    '--heartbeat-file', $paths.HeartbeatFile
  )
  if ($IncludeProgressRegex -and $ProgressRegex) {
    $progressArgument = $ProgressRegex.Replace(' ', '')
    $args += @('--progress-regex', $progressArgument)
  }
  $si = New-Object System.Diagnostics.ProcessStartInfo
  $si.FileName = $node.Source
  $si.UseShellExecute = $false
  $si.CreateNoWindow = $true
  $si.RedirectStandardOutput = $true
  $si.RedirectStandardError  = $true
  foreach ($arg in $args) { $null = $si.ArgumentList.Add($arg) }
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $si
  $null = $p.Start()
  # async copy to files
  $outStream = [System.IO.StreamWriter]::new($paths.OutFile, $true)
  $errStream = [System.IO.StreamWriter]::new($paths.ErrFile, $true)
  $null = $p.StandardOutput.BaseStream.CopyToAsync($outStream.BaseStream)
  $null = $p.StandardError.BaseStream.CopyToAsync($errStream.BaseStream)
  $pidObj = [ordered]@{
    schema    = 'dev-watcher/pid-v1'
    pid       = $p.Id
    startedAt = (Get-Date).ToString('o')
    nodePath  = $node.Source
    script    = $script
    args      = $args
    outFile   = $paths.OutFile
    errFile   = $paths.ErrFile
    statusFile = $paths.StatusFile
    heartbeatFile = $paths.HeartbeatFile
  }
  ($pidObj | ConvertTo-Json -Depth 5) | Out-File -FilePath $paths.PidFile -Encoding utf8
  Write-Host ("Started dev watcher (PID {0})" -f $p.Id)
  return $p.Id
}

function Stop-DevWatcher {
  param([string]$ResultsDir)
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $pidObj = Read-JsonFile -Path $paths.PidFile
  if ($pidObj -and $pidObj.pid -is [int]) {
    if (Test-ProcessAlive -Pid $pidObj.pid) {
      try { Stop-Process -Id $pidObj.pid -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Host 'Stopped dev watcher.'
  } else {
    Write-Host 'No dev watcher PID found.'
  }
  # Always clear files regardless of PID state
  Remove-Item -LiteralPath $paths.PidFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $paths.StatusFile -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $paths.HeartbeatFile -Force -ErrorAction SilentlyContinue
}

function Get-DevWatcherStatus {
  param([string]$ResultsDir)
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $pidObj = Read-JsonFile -Path $paths.PidFile
  $watcherPid = if ($pidObj -and $pidObj.pid -is [int]) { [int]$pidObj.pid } else { $null }
  $alive = $false
  $procInfo = $null
  $validation = $null
  if ($watcherPid) {
    $alive = Test-ProcessAlive -Pid $watcherPid
    if ($alive) {
      $procInfo = Get-WatcherProcessInfo -Pid $watcherPid
      $validation = Test-WatcherProcess -ProcessInfo $procInfo -Paths $paths
    }
  }

  $statusData = Read-JsonFile -Path $paths.StatusFile
  $heartbeatData = Read-JsonFile -Path $paths.HeartbeatFile
  $heartbeatTimestamp = Get-PropValue $heartbeatData 'timestamp'
  $stateFromStatus = Get-PropValue $statusData 'state'
  $state = if ($stateFromStatus) { $stateFromStatus } elseif ($alive) { 'ok' } else { 'stopped' }
  $metrics = Get-PropValue $statusData 'metrics'
  if (-not $metrics) { $metrics = @{} }
  $thresholdData = Get-PropValue $statusData 'thresholds'
  $thresholds = if ($thresholdData) { $thresholdData } else {
    @{
      warnSeconds = $null
      hangSeconds = $null
      noProgressSeconds = $null
      pollMs = $null
    }
  }

  $heartbeatAgeSeconds = $null
  $heartbeatFresh = $false
  $heartbeatReason = $null
  if ($heartbeatTimestamp) {
    try {
      $culture = [System.Globalization.CultureInfo]::InvariantCulture
      $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      $heartbeatMoment = [datetime]::Parse($heartbeatTimestamp, $culture, $styles)
      $ageSpan = ([datetime]::UtcNow) - $heartbeatMoment
      $ageSecondsValue = $null
      if ($ageSpan.TotalSeconds -ge 0) {
        $ageSecondsValue = [int][math]::Floor($ageSpan.TotalSeconds)
        $heartbeatAgeSeconds = $ageSecondsValue
      }
      $pollSeconds = $null
      if ($thresholds -and $thresholds.pollMs) {
        $pollSeconds = [double]$thresholds.pollMs / 1000.0
      }
      $staleSeconds = if ($pollSeconds -and $pollSeconds -gt 0) {
        [int][math]::Ceiling($pollSeconds * 4)
      } else { 10 }
      if ($ageSpan.TotalSeconds -ge 0 -and $ageSpan.TotalSeconds -le $staleSeconds) {
        $heartbeatFresh = $true
      } else {
        $ageForReason = if ($ageSecondsValue -ne $null) { $ageSecondsValue } else { [int][math]::Floor([math]::Max($ageSpan.TotalSeconds, 0)) }
        $heartbeatReason = "[heartbeat] stale (~${ageForReason}s)"
      }
    } catch {
      $heartbeatReason = '[heartbeat] timestamp parse failed'
    }
  } else {
    $heartbeatReason = '[heartbeat] missing'
  }

  $outInfo = Get-LogSnapshot -Path $paths.OutFile
  $errInfo = Get-LogSnapshot -Path $paths.ErrFile
  $needsTrim = ($outInfo.exists -and $outInfo.sizeBytes -gt $MaxLogBytes) -or ($errInfo.exists -and $errInfo.sizeBytes -gt $MaxLogBytes)

  $processVerified = if ($validation) { $validation.IsValid } else { $false }
  $verificationReason = if ($validation) { $validation.Reason } else { $null }
  if ($processVerified -and -not $heartbeatFresh) {
    $processVerified = $false
    if ($heartbeatReason) {
      $verificationReason = if ($verificationReason) { "$verificationReason; $heartbeatReason" } else { $heartbeatReason }
    }
  } elseif (-not $processVerified -and -not $verificationReason -and -not $heartbeatFresh -and $heartbeatReason) {
    $verificationReason = $heartbeatReason
  }

  $obj = [ordered]@{
    schema = 'dev-watcher/status-v2'
    timestamp = (Get-Date).ToString('o')
    alive  = $alive
    pid    = $watcherPid
    verifiedProcess = $processVerified
    verificationReason = $verificationReason
    state  = if ($alive) { $state } else { 'stopped' }
    startedAt = if ($statusData) { Get-PropValue $statusData 'startedAt' } elseif ($pidObj) { $pidObj.startedAt } else { $null }
    lastActivityAt = Get-PropValue $metrics 'lastActivityAt'
    lastProgressAt = Get-PropValue $metrics 'lastProgressAt'
    lastSummaryAt = Get-PropValue $metrics 'lastSummaryAt'
    lastHangWatchAt = Get-PropValue $metrics 'lastHangWatchAt'
    lastHangSuspectAt = Get-PropValue $metrics 'lastHangSuspectAt'
    lastBusyWatchAt = Get-PropValue $metrics 'lastBusyWatchAt'
    lastBusySuspectAt = Get-PropValue $metrics 'lastBusySuspectAt'
    bytesSinceProgress = Get-PropValue $metrics 'bytesSinceProgress'
    lastHeartbeatAt = $heartbeatTimestamp
    heartbeatAgeSeconds = $heartbeatAgeSeconds
    heartbeatFresh = $heartbeatFresh
    heartbeatReason = $heartbeatReason
    thresholds = $thresholds
    files = @{ 
      pid = @{ path = $paths.PidFile }
      status = @{ path = $paths.StatusFile; exists = [bool]$statusData }
      heartbeat = @{
        path = $paths.HeartbeatFile
        exists = [bool]$heartbeatData
        timestamp = $heartbeatTimestamp
        ageSeconds = $heartbeatAgeSeconds
        schema = Get-PropValue $heartbeatData 'schema'
      }
      out = $outInfo
      err = $errInfo
    }
    process = @{
      commandLine = Get-PropValue $procInfo 'CommandLine'
      path = Get-PropValue $procInfo 'Path'
      verified = $processVerified
    }
    needsTrim = $needsTrim
  }
  return ($obj | ConvertTo-Json -Depth 6)
}

if ($Ensure) {
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $pidObj = Read-JsonFile -Path $paths.PidFile
  $needStart = $true
  if ($pidObj -and $pidObj.pid -is [int]) {
    $alive = Test-ProcessAlive -Pid $pidObj.pid
    if ($alive) {
      $procInfo = Get-WatcherProcessInfo -Pid $pidObj.pid
      $validation = Test-WatcherProcess -ProcessInfo $procInfo -Paths $paths
      if ($validation.IsValid) {
        $statusDataEnsure = Read-JsonFile -Path $paths.StatusFile
        $thresholdDataEnsure = Get-PropValue $statusDataEnsure 'thresholds'
        $pollMsEnsure = if ($thresholdDataEnsure) { Get-PropValue $thresholdDataEnsure 'pollMs' } else { $null }
        $heartbeatEnsure = Read-JsonFile -Path $paths.HeartbeatFile
        $heartbeatTimestampEnsure = Get-PropValue $heartbeatEnsure 'timestamp'
        $hbFresh = $false
        $hbReason = '[heartbeat] missing'
        if ($heartbeatTimestampEnsure) {
          try {
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            $hbMoment = [datetime]::Parse($heartbeatTimestampEnsure, $culture, $styles)
            $ageSpan = ([datetime]::UtcNow) - $hbMoment
            $pollSecondsEnsure = if ($pollMsEnsure) { [double]$pollMsEnsure / 1000.0 } else { $null }
            $staleSecondsEnsure = if ($pollSecondsEnsure -and $pollSecondsEnsure -gt 0) { [int][math]::Ceiling($pollSecondsEnsure * 4) } else { 10 }
            if ($ageSpan.TotalSeconds -ge 0 -and $ageSpan.TotalSeconds -le $staleSecondsEnsure) {
              $hbFresh = $true
            } else {
              $hbReason = "[heartbeat] stale (~$([int][math]::Floor([math]::Max($ageSpan.TotalSeconds,0))))s)"
            }
          } catch {
            $hbReason = '[heartbeat] timestamp parse failed'
          }
        }
        if ($hbFresh) {
          $needStart = $false
        } else {
          Write-Warning "[watcher] ${hbReason}. Restarting."
          Stop-DevWatcher -ResultsDir $ResultsDir | Out-Null
          $needStart = $true
        }
      } else {
        Write-Warning "[watcher] Existing process did not match expectations: $($validation.Reason). Restarting."
        Stop-DevWatcher -ResultsDir $ResultsDir | Out-Null
        $needStart = $true
      }
    }
  }
  if ($needStart) {
    $includeRegex = $PSBoundParameters.ContainsKey('ProgressRegex')
    Start-DevWatcher -ResultsDir $ResultsDir -WarnSeconds $WarnSeconds -HangSeconds $HangSeconds -PollMs $PollMs -NoProgressSeconds $NoProgressSeconds -ProgressRegex $ProgressRegex -IncludeProgressRegex:$includeRegex | Out-Null
  } else {
    Write-Host ("Dev watcher already running (PID {0})." -f $pidObj.pid)
  }
}
elseif ($Stop) {
  Stop-DevWatcher -ResultsDir $ResultsDir
}
elseif ($Status) {
  Get-DevWatcherStatus -ResultsDir $ResultsDir | Write-Host
}
elseif ($Trim) {
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $trimmed = $false
  foreach ($logPath in @($paths.OutFile, $paths.ErrFile)) {
    try {
      if (Trim-LogFile -Path $logPath) { $trimmed = $true }
    } catch {
      Write-Warning ("[watcher] Failed to trim log {0}: {1}" -f $logPath, $_.Exception.Message)
    }
  }
  if ($trimmed) { Write-Host 'Trimmed watcher logs.' } else { Write-Host 'No trimming needed.' }
}
elseif ($AutoTrim) {
  $statusJson = Get-DevWatcherStatus -ResultsDir $ResultsDir
  $status = $null
  try { $status = $statusJson | ConvertFrom-Json -ErrorAction Stop } catch {}
  if ($status -and $status.needsTrim) {
    $paths = Get-WatcherPaths -ResultsDir $ResultsDir
    $trimmed = $false
    foreach ($logPath in @($paths.OutFile, $paths.ErrFile)) {
      try {
        if (Trim-LogFile -Path $logPath) { $trimmed = $true }
      } catch {
        Write-Warning ("[watcher] Failed to trim log {0}: {1}" -f $logPath, $_.Exception.Message)
      }
    }
    if ($trimmed) { Write-Host 'Trimmed watcher logs.' } else { Write-Host 'No trimming needed.' }
  } else {
    Write-Host 'No trimming needed.'
  }
}
else {
  Write-Host 'Usage:'
  Write-Host '  Ensure watcher:  pwsh -File tools/Dev-WatcherManager.ps1 -Ensure'
  Write-Host '  Show status:     pwsh -File tools/Dev-WatcherManager.ps1 -Status'
  Write-Host '  Stop watcher:    pwsh -File tools/Dev-WatcherManager.ps1 -Stop'
  Write-Host '  Trim logs:       pwsh -File tools/Dev-WatcherManager.ps1 -Trim'
  Write-Host '  Auto-trim if needed: pwsh -File tools/Dev-WatcherManager.ps1 -AutoTrim'
}



