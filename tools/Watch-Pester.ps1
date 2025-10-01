[CmdletBinding()]
param(
    [string]$Path = '.',
    [string]$Filter = '*.ps1',
    [int]$DebounceMilliseconds = 400,
    [switch]$RunAllOnStart,
    [switch]$NoSummary,
    [string]$TestPath = 'tests',
    [string]$Tag,
    [string]$ExcludeTag,
    [switch]$Quiet,
    [switch]$SingleRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
  param([string]$Msg,[string]$Level='INFO')
  if ($Quiet -and $Level -eq 'INFO') { return }
  $ts = (Get-Date).ToString('HH:mm:ss')
  Write-Host "[$ts][$Level] $Msg"
}

function Invoke-PesterSelective {
  param([string[]]$ChangedFiles)
  if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Log 'Pester not found; installing locally (CurrentUser).' 'WARN'
    Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -ErrorAction Stop
  }
  Import-Module Pester -ErrorAction Stop | Out-Null

  $config = New-PesterConfiguration
  $config.Run.PassThru = $true
  $config.Run.Path = $TestPath
  if ($Tag) { $config.Filter.Tag = @($Tag) }
  if ($ExcludeTag) { $config.Filter.ExcludeTag = @($ExcludeTag) }
  $config.Output.Verbosity = if ($Quiet) { 'Normal' } else { 'Detailed' }

  # Derive targeted test files if changed files include tests or source mapping.
  $testFiles = @()
  foreach ($f in $ChangedFiles) {
    if ($f -match '\\tests\\.+\.Tests\.ps1$') { $testFiles += $f }
  }
  if ($testFiles.Count -gt 0) {
    $config.Run.Path = $testFiles
    Write-Log "Targeted test run: $($testFiles.Count) file(s)" 'INFO'
  } else {
    Write-Log 'No specific test files changed; running full test suite scope' 'INFO'
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $result = $null
  try {
    $result = Invoke-Pester -Configuration $config -ErrorAction Stop
  } catch {
    Write-Log "Pester invocation threw: $($_.Exception.Message)" 'ERROR'
  } finally {
    $sw.Stop()
  }
  if ($null -eq $result) {
    Write-Log 'No result object (likely discovery failure).' 'ERROR'
    return
  }
  $failedCount = ($result | Add-Member -PassThru -NotePropertyName dummy 0 | Select-Object -ExpandProperty FailedCount -ErrorAction SilentlyContinue)
  $failedBlocks = ($result | Select-Object -ExpandProperty FailedBlocksCount -ErrorAction SilentlyContinue)
  $testCount = ($result | Select-Object -ExpandProperty TestCount -ErrorAction SilentlyContinue)
  $skipped = ($result | Select-Object -ExpandProperty SkippedCount -ErrorAction SilentlyContinue)
  $status = if (($failedCount -as [int]) -gt 0 -or ($failedBlocks -as [int]) -gt 0) { 'FAIL' } else { 'PASS' }
  Write-Log "Pester run ${status} in $([Math]::Round($sw.Elapsed.TotalSeconds,2))s (Tests=$testCount Failed=$failedCount)" 'INFO'
  if (-not $NoSummary) {
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host ("Tests: {0}  Failed: {1}  Skipped: {2}  Duration: {3:N2}s" -f $testCount,$failedCount,$skipped,$sw.Elapsed.TotalSeconds)
  }
}

if ($SingleRun) {
  Write-Log 'Single run mode' 'INFO'
  Invoke-PesterSelective -ChangedFiles @()
  exit 0
}

$fullPath = Resolve-Path -LiteralPath $Path
Write-Log "Watching path: $fullPath (filter=$Filter)" 'INFO'

if ($RunAllOnStart) {
  Invoke-PesterSelective -ChangedFiles @()
}

$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $fullPath
$fsw.Filter = $Filter
$fsw.IncludeSubdirectories = $true
$fsw.EnableRaisingEvents = $true

$pending = $null
$lastRun = Get-Date 0
$debounce = [TimeSpan]::FromMilliseconds($DebounceMilliseconds)

Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier FSWChanged -Action {
  $script:pending = (Get-Date)
} | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier FSWCreated -Action {
  $script:pending = (Get-Date)
} | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Deleted -SourceIdentifier FSWDeleted -Action {
  $script:pending = (Get-Date)
} | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier FSWRenamed -Action {
  $script:pending = (Get-Date)
} | Out-Null

Write-Log 'Watcher active. Press Ctrl+C to exit.' 'INFO'

try {
  while ($true) {
    Start-Sleep -Milliseconds 150
    if ($pending -and ((Get-Date) - $pending) -ge $debounce) {
      $since = (Get-Date) - $lastRun
      Write-Log "Change batch stabilized (since last run $([Math]::Round($since.TotalSeconds,2))s). Collecting changed files..." 'INFO'
      # Collect changed files between last run and now
      $changed = Get-ChildItem -Path $fullPath -Recurse -File | Where-Object { $_.LastWriteTime -gt $lastRun } | Select-Object -ExpandProperty FullName
      $lastRun = Get-Date
      $pending = $null
      if ($changed.Count -eq 0) {
        Write-Log 'No changed files detected (possibly delete or rename only).' 'INFO'
      }
      Invoke-PesterSelective -ChangedFiles $changed
    }
  }
} finally {
  Unregister-Event -SourceIdentifier FSWChanged -ErrorAction SilentlyContinue
  Unregister-Event -SourceIdentifier FSWCreated -ErrorAction SilentlyContinue
  Unregister-Event -SourceIdentifier FSWDeleted -ErrorAction SilentlyContinue
  Unregister-Event -SourceIdentifier FSWRenamed -ErrorAction SilentlyContinue
  $fsw.Dispose()
  Write-Log 'Watcher disposed.' 'INFO'
}
