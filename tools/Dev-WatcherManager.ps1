param(
  [switch]$Ensure,
  [switch]$Stop,
  [switch]$Status,
  [string]$ResultsDir = 'tests/results',
  [int]$WarnSeconds = 60,
  [int]$HangSeconds = 120,
  [int]$PollMs = 2000,
  [int]$NoProgressSeconds = 90,
  [string]$ProgressRegex = '^(?:\s*\[[-+\*]\]|\s*It\s)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Start-DevWatcher {
  param([string]$ResultsDir,[int]$WarnSeconds,[int]$HangSeconds,[int]$PollMs,[int]$NoProgressSeconds,[string]$ProgressRegex)
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
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
    '--progress-regex', $ProgressRegex
  )
  $si = New-Object System.Diagnostics.ProcessStartInfo
  $si.FileName = $node.Source
  $si.Arguments = ($args -join ' ')
  $si.UseShellExecute = $false
  $si.CreateNoWindow = $true
  $si.RedirectStandardOutput = $true
  $si.RedirectStandardError  = $true
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
    Remove-Item -LiteralPath $paths.PidFile -Force -ErrorAction SilentlyContinue
    Write-Host 'Stopped dev watcher.'
  } else {
    Write-Host 'No dev watcher PID found.'
  }
}

function Get-DevWatcherStatus {
  param([string]$ResultsDir)
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $pidObj = Read-JsonFile -Path $paths.PidFile
  $alive = $false
  if ($pidObj -and $pidObj.pid -is [int]) { $alive = Test-ProcessAlive -Pid $pidObj.pid }
  $outTail = if (Test-Path $paths.OutFile) { Get-Content -LiteralPath $paths.OutFile -Tail 200 } else { @() }
  $errTail = if (Test-Path $paths.ErrFile) { Get-Content -LiteralPath $paths.ErrFile -Tail 200 } else { @() }
  $now = Get-Date
  $state = 'ok'
  $lastBusy = ($errTail | Select-String -SimpleMatch '[busy-suspect]' | Select-Object -Last 1).ToString()
  $lastHang = ($errTail | Select-String -SimpleMatch '[hang-suspect]' | Select-Object -Last 1).ToString()
  if ($lastBusy) { $state = 'busy-suspect' }
  elseif ($lastHang) { $state = 'hang-suspect' }
  elseif ($errTail | Select-String -SimpleMatch '[busy-watch]') { $state = 'busy-watch' }
  elseif ($outTail | Select-String -SimpleMatch '[hang-watch]') { $state = 'hang-watch' }
  $obj = [ordered]@{
    schema = 'dev-watcher/status-v1'
    alive  = $alive
    pid    = if ($pidObj) { $pidObj.pid } else { $null }
    state  = $state
    out    = @{ path = $paths.OutFile }
    err    = @{ path = $paths.ErrFile }
    startedAt = if ($pidObj) { $pidObj.startedAt } else { $null }
  }
  return ($obj | ConvertTo-Json -Depth 5)
}

if ($Ensure) {
  $paths = Get-WatcherPaths -ResultsDir $ResultsDir
  $pidObj = Read-JsonFile -Path $paths.PidFile
  $needStart = $true
  if ($pidObj -and $pidObj.pid -is [int]) { $needStart = -not (Test-ProcessAlive -Pid $pidObj.pid) }
  if ($needStart) { Start-DevWatcher -ResultsDir $ResultsDir -WarnSeconds $WarnSeconds -HangSeconds $HangSeconds -PollMs $PollMs -NoProgressSeconds $NoProgressSeconds -ProgressRegex $ProgressRegex | Out-Null }
  else { Write-Host ("Dev watcher already running (PID {0})." -f $pidObj.pid) }
}
elseif ($Stop) {
  Stop-DevWatcher -ResultsDir $ResultsDir
}
elseif ($Status) {
  Get-DevWatcherStatus -ResultsDir $ResultsDir | Write-Host
}
else {
  Write-Host 'Usage:'
  Write-Host '  Ensure watcher:  pwsh -File tools/Dev-WatcherManager.ps1 -Ensure'
  Write-Host '  Show status:     pwsh -File tools/Dev-WatcherManager.ps1 -Status'
  Write-Host '  Stop watcher:    pwsh -File tools/Dev-WatcherManager.ps1 -Stop'
}

