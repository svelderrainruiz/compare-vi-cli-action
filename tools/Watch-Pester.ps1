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
  [switch]$SingleRun,
  [switch]$ChangedOnly,
  [switch]$BeepOnFail,
  [switch]$InferTestsFromSource
  , [string]$DeltaJsonPath
  , [switch]$ShowFailed
  , [int]$MaxFailedList = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
  param([string]$Msg,[string]$Level='INFO')
  if ($Quiet -and $Level -eq 'INFO') { return }
  $ts = (Get-Date).ToString('HH:mm:ss')
  Write-Host "[$ts][$Level] $Msg"
}

${script:LastRunStats} = $null
${script:RunSequence} = 0

function Invoke-PesterSelective {
  param([string[]]$ChangedFiles)
  # Normalize to array to avoid property access issues under StrictMode when empty or single string
  $ChangedFiles = @($ChangedFiles | Where-Object { $_ -ne $null -and $_ -ne '' })
  function Get-ItemCount { param($o) if ($null -eq $o) { return 0 } return (@($o)).Length }
  Write-Log "DEBUG Enter Invoke-PesterSelective; ChangedFiles count=$(Get-ItemCount $ChangedFiles)" 'DEBUG'
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

  # Derive targeted test files if changed files include tests or inferred source mapping.
  $testFiles = @()
  foreach ($f in $ChangedFiles) {
    if ($f -match '\\tests\\.+\.Tests\.ps1$') { $testFiles += $f }
  }
  if ($InferTestsFromSource -and (Get-ItemCount $ChangedFiles) -gt 0) {
    foreach ($src in $ChangedFiles) {
      if ($src -match '\\module\\.+\\([^\\]+)\.psm1$') {
        $baseName = $Matches[1]
        $candidate = Join-Path (Resolve-Path -LiteralPath $TestPath) ("${baseName}.Tests.ps1")
        if (Test-Path -LiteralPath $candidate) { $testFiles += (Resolve-Path $candidate).Path }
      } elseif ($src -match '\\scripts\\([^\\]+)\.ps1$') {
        $baseName = $Matches[1]
        $candidate = Join-Path (Resolve-Path -LiteralPath $TestPath) ("${baseName}.Tests.ps1")
        if (Test-Path -LiteralPath $candidate) { $testFiles += (Resolve-Path $candidate).Path }
      }
    }
  }
  $testFiles = $testFiles | Sort-Object -Unique
  $testFileCount = (Get-ItemCount $testFiles)
  if ($testFileCount -gt 0) {
    $config.Run.Path = $testFiles
    Write-Log "Targeted test run: $testFileCount file(s)" 'INFO'
  } else {
    if ($ChangedOnly) {
      Write-Log 'ChangedOnly set and no targeted test files inferred; skipping run.' 'INFO'
      return
    }
    Write-Log 'No targeted tests inferred; running full test suite scope' 'INFO'
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
  if (-not $testCount) { $testCount = ($result | Select-Object -ExpandProperty TotalCount -ErrorAction SilentlyContinue) }
  if (-not $testCount -and ($result.Tests)) { $testCount = (@($result.Tests)).Length }
  if (-not $testCount) {
    # Last resort: sum passed+failed+skipped if available
    try {
      $passed = ($result | Select-Object -ExpandProperty PassedCount -ErrorAction SilentlyContinue)
      $sk = ($result | Select-Object -ExpandProperty SkippedCount -ErrorAction SilentlyContinue)
      $fl = $failedCount
      if ($passed -or $fl -or $sk) { $testCount = (($passed|ForEach-Object {[int]$_}) + ($fl|ForEach-Object {[int]$_}) + ($sk|ForEach-Object {[int]$_})) }
    } catch {}
  }
  $skipped = ($result | Select-Object -ExpandProperty SkippedCount -ErrorAction SilentlyContinue)
  $status = if (($failedCount -as [int]) -gt 0 -or ($failedBlocks -as [int]) -gt 0) { 'FAIL' } else { 'PASS' }

  $prev = $script:LastRunStats
  $deltaText = ''
  if ($prev) {
    $dTests = ($testCount - $prev.Tests)
    $dFailed = ($failedCount - $prev.Failed)
    $dSkipped = ($skipped - $prev.Skipped)
    $deltaText = " (Δ Tests=$dTests Failed=$dFailed Skipped=$dSkipped)"
  }
  $script:RunSequence++

  # Colorized status line
  $elapsedSec = [Math]::Round($sw.Elapsed.TotalSeconds,2)
  $statusColor = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
  $line = "Run #$(${script:RunSequence}) $status in ${elapsedSec}s (Tests=$testCount Failed=$failedCount)$deltaText"
  if (-not $Quiet) { Write-Host $line -ForegroundColor $statusColor } else { Write-Log $line 'INFO' }
  if ($BeepOnFail -and $status -eq 'FAIL') {
    try { [console]::beep(440,220) } catch { Write-Log 'Beep failed (non-interactive console?)' 'WARN' }
  }
  if ($DeltaJsonPath) {
    try {
      $payload = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        status = $status
        stats = [ordered]@{ tests = $testCount; failed = $failedCount; skipped = $skipped }
        previous = if ($prev) { [ordered]@{ tests=$prev.Tests; failed=$prev.Failed; skipped=$prev.Skipped } } else { $null }
        delta = if ($prev) { [ordered]@{ tests=$dTests; failed=$dFailed; skipped=$dSkipped } } else { $null }
        classification = if ($prev) {
          if ($dFailed -lt 0) { 'improved' } elseif ($dFailed -gt 0) { 'worsened' } else { 'unchanged' }
        } else { 'baseline' }
        runSequence = $script:RunSequence
      }
      $json = $payload | ConvertTo-Json -Depth 5
      $outDir = Split-Path -Parent $DeltaJsonPath
      if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
      $json | Set-Content -NoNewline -LiteralPath $DeltaJsonPath -Encoding UTF8
      Write-Log "Wrote delta JSON: $DeltaJsonPath" 'INFO'
    } catch {
      Write-Log "Failed writing delta JSON: $($_.Exception.Message)" 'WARN'
    }
  }
  $script:LastRunStats = [pscustomobject]@{ Tests=$testCount; Failed=$failedCount; Skipped=$skipped }
  if (-not $NoSummary) {
    Write-Host "--- Summary ---" -ForegroundColor Cyan
    Write-Host ("Tests: {0}  Failed: {1}  Skipped: {2}  Duration: {3:N2}s" -f $testCount,$failedCount,$skipped,$sw.Elapsed.TotalSeconds)
    if ($ShowFailed -and ($failedCount -gt 0)) {
      $max = if ($MaxFailedList -and $MaxFailedList -gt 0) { $MaxFailedList } else { 10 }
      try {
        $failedTests = $result.Tests | Where-Object { $_.Result -eq 'Failed' } | Select-Object -First $max
        if ($failedTests) {
          Write-Host "-- Failed Tests (up to $max) --" -ForegroundColor Red
          foreach ($ft in $failedTests) {
            Write-Host (" • {0}" -f ($ft.Path -replace [regex]::Escape((Resolve-Path .).Path),'').TrimStart('\\')) -ForegroundColor Red
          }
        }
      } catch { Write-Log "Failed enumerating failed tests: $($_.Exception.Message)" 'WARN' }
    }
  }
}

if ($SingleRun) {
  Write-Log 'Single run mode' 'INFO'
  if ($ChangedOnly) {
    Write-Log 'ChangedOnly set with no changed files context; skipping test run.' 'INFO'
    exit 0
  }
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
      $changedCount = (@($changed)).Length
      if ($changedCount -eq 0) {
        Write-Log 'No changed files detected (possibly delete or rename only).' 'INFO'
      }
      Write-Log "DEBUG Dispatching Invoke-PesterSelective with changedCount=$changedCount" 'DEBUG'
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
