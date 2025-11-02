#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$BaseVi,
  [Parameter(Mandatory = $true)][string]$HeadVi,
[ValidateSet('normal','cli-suppressed','git-context','duplicate-window')]
[string]$Mode = 'normal',
[int]$SentinelTtlSeconds = 60,
[switch]$RenderReport,
[switch]$UseStub,
[switch]$ProbeSetup,
[switch]$AutoConfig,
[switch]$Stateless,
[string]$LabVIEWVersion,
[ValidateSet('32','64')]
[string]$LabVIEWBitness,
[ValidateSet('full','legacy')]
[string]$NoiseProfile = 'full',
[string]$ResultsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  try { return (git -C (Get-Location).Path rev-parse --show-toplevel 2>$null).Trim() } catch { return (Get-Location).Path }
}

function Get-TempSentinelRoot {
  try { return Join-Path ([System.IO.Path]::GetTempPath()) 'comparevi-cli-sentinel' } catch { return Join-Path $env:TEMP 'comparevi-cli-sentinel' }
}

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Remove-LocalConfig {
  param([Parameter(Mandatory = $true)][string]$RepoRoot)

  $localConfig = Join-Path $RepoRoot 'configs' 'labview-paths.local.json'
  if (Test-Path -LiteralPath $localConfig -PathType Leaf) {
    Remove-Item -LiteralPath $localConfig -Force -ErrorAction SilentlyContinue
  }
}

function Get-CompareCliSentinelPath {
  param(
    [Parameter(Mandatory = $true)][string]$Vi1,
    [Parameter(Mandatory = $true)][string]$Vi2,
    [string]$ReportPath
  )

  $root = Get-TempSentinelRoot
  Ensure-Directory -Path $root

  $key = ($Vi1.Trim().ToLowerInvariant()) + '|' + ($Vi2.Trim().ToLowerInvariant()) + '|' + ([string]($ReportPath ?? '')).Trim().ToLowerInvariant()
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
  $hash = ($sha1.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
  return Join-Path $root ($hash + '.sentinel')
}

function Touch-CompareCliSentinel {
  param(
    [Parameter(Mandatory = $true)][string]$Vi1,
    [Parameter(Mandatory = $true)][string]$Vi2,
    [string]$ReportPath
  )

  try {
    $path = Get-CompareCliSentinelPath -Vi1 $Vi1 -Vi2 $Vi2 -ReportPath $ReportPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      New-Item -ItemType File -Path $path -Force | Out-Null
    }
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = [DateTime]::UtcNow
    return $path
  } catch {
    return $null
  }
}

function Get-SentinelSkipStatus {
  param(
    [Parameter(Mandatory = $true)][string]$Vi1,
    [Parameter(Mandatory = $true)][string]$Vi2,
    [string]$ReportPath,
    [int]$TtlSeconds
  )

  $path = Get-CompareCliSentinelPath -Vi1 $Vi1 -Vi2 $Vi2 -ReportPath $ReportPath
  if ($TtlSeconds -le 0 -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ skipped = $false; reason = $null; path = $path }
  }

  try {
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    $age = [Math]::Abs((New-TimeSpan -Start $item.LastWriteTimeUtc -End ([DateTime]::UtcNow)).TotalSeconds)
    if ($age -le $TtlSeconds) {
      return [pscustomobject]@{ skipped = $true; reason = "sentinel:$TtlSeconds"; path = $path }
    }
  } catch {}

  return [pscustomobject]@{ skipped = $false; reason = $null; path = $path }
}

function Get-LocalDiffProcessSnapshot {
  $names = @('LabVIEW','LVCompare','LabVIEWCLI','g-cli')
  $snapshot = New-Object System.Collections.Generic.List[object]
  foreach ($name in $names) {
    try {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
      foreach ($proc in $procs) {
        $info = [ordered]@{ name = $proc.ProcessName; id = $proc.Id }
        try { $info.startTime = $proc.StartTime } catch {}
        $snapshot.Add([pscustomobject]$info)
      }
    } catch {}
  }
  return $snapshot.ToArray()
}

function Read-FileSnippet {
  param(
    [string]$Path,
    [int]$MaxLength = 200
  )

  if (-not $Path) { return $null }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ($content.Length -le $MaxLength) { return $content }
    return $content.Substring(0, $MaxLength)
  } catch { return $null }
}

$repoRoot = Resolve-RepoRoot
if (-not $repoRoot) { throw 'Unable to determine repository root.' }

if ($Stateless.IsPresent) {
  Remove-LocalConfig -RepoRoot $repoRoot
}

$localConfigPath = Join-Path $repoRoot 'configs' 'labview-paths.local.json'

$driverPath = Join-Path $repoRoot 'tools' 'Invoke-LVCompare.ps1'
if (-not (Test-Path -LiteralPath $driverPath -PathType Leaf)) {
  throw "Invoke-LVCompare.ps1 not found at $driverPath"
}

function Resolve-ViPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $candidates = New-Object System.Collections.Generic.List[string]
  if ([System.IO.Path]::IsPathRooted($Path)) {
    $candidates.Add($Path)
  } else {
    $candidates.Add((Join-Path $repoRoot $Path))
  }

  if ($Path -match '^tests[\\/](.+)$') {
    $relative = $Matches[1]
    $candidates.Add((Join-Path $repoRoot $relative))
  }

  foreach ($candidate in $candidates) {
    try {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
      }
    } catch {}
  }

  throw ("VI not found. Tried: {0}" -f ($candidates -join '; '))
}

$BaseVi = Resolve-ViPath -Path $BaseVi
$HeadVi = Resolve-ViPath -Path $HeadVi

$setupStatus = [ordered]@{
  ok = $true
  message = 'ready'
}

function Invoke-SetupProbe {
  param([switch]$SuppressWarning)

  $status = [ordered]@{
    ok = $true
    message = 'ready'
  }

  $setupScript = Join-Path $repoRoot 'tools' 'Verify-LVCompareSetup.ps1'
  if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    $status.ok = $false
    $status.message = 'Verify-LVCompareSetup.ps1 not found'
    return [pscustomobject]$status
  }

  try {
    & $setupScript -ProbeCli | Out-Null
    if ($LASTEXITCODE -ne 0) {
      $status.ok = $false
      $status.message = "LVCompare setup probe exited with code $LASTEXITCODE"
    }
  } catch {
    $status.ok = $false
    $status.message = $_.Exception.Message
  }
  if (-not $status.ok -and -not $SuppressWarning) {
    Write-Warning ("LVCompare setup probe failed: {0}" -f $status.message)
  }
  return [pscustomobject]$status
}

if ($ProbeSetup.IsPresent) {
  $setupStatus = Invoke-SetupProbe
}

Write-Verbose ("Requested LabVIEW version: {0}" -f ($LabVIEWVersion ?? '(none)'))
Write-Verbose ("Requested LabVIEW bitness: {0}" -f ($LabVIEWBitness ?? '(none)'))

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
    [Parameter(Mandatory = $true)][string]$RunDir,
    [Parameter(Mandatory = $true)][string]$Mode,
    [switch]$RenderReport,
    [switch]$UseStub,
    [int]$SentinelTtlSeconds = 0,
    [ValidateSet('full','legacy')]
    [string]$NoiseProfile = 'full'
  )

  New-Item -ItemType Directory -Path $RunDir -Force | Out-Null

  $prev = @{
    COMPAREVI_NO_CLI_CAPTURE    = $env:COMPAREVI_NO_CLI_CAPTURE
    COMPAREVI_SUPPRESS_CLI_IN_GIT = $env:COMPAREVI_SUPPRESS_CLI_IN_GIT
    COMPAREVI_WARN_CLI_IN_GIT   = $env:COMPAREVI_WARN_CLI_IN_GIT
    COMPAREVI_CLI_SENTINEL_TTL  = $env:COMPAREVI_CLI_SENTINEL_TTL
    GIT_DIR  = $env:GIT_DIR
    GIT_PREFIX = $env:GIT_PREFIX
  }

  $baseResolved = (Resolve-Path -LiteralPath $BaseVi).Path
  $headResolved = (Resolve-Path -LiteralPath $HeadVi).Path

  switch ($Mode) {
    'cli-suppressed' { $env:COMPAREVI_NO_CLI_CAPTURE = '1' }
    'git-context'    { $env:COMPAREVI_SUPPRESS_CLI_IN_GIT = '1'; $env:COMPAREVI_WARN_CLI_IN_GIT = '1'; if (-not $env:GIT_DIR) { $env:GIT_DIR = '.' } }
    default { }
  }

  $forcedTtl = if ($SentinelTtlSeconds -gt 0) { $SentinelTtlSeconds } else { 0 }
  $effectiveTtlUsed = 0
  if ($forcedTtl -gt 0) {
    $env:COMPAREVI_CLI_SENTINEL_TTL = [string]$forcedTtl
    $effectiveTtlUsed = $forcedTtl
  } elseif ($env:COMPAREVI_CLI_SENTINEL_TTL) {
    $tmp = 0
    if ([int]::TryParse($env:COMPAREVI_CLI_SENTINEL_TTL, [ref]$tmp)) { $effectiveTtlUsed = $tmp }
  }

  $preSnapshot = Get-LocalDiffProcessSnapshot

  try {
    $params = @{
      BaseVi    = $baseResolved
      HeadVi    = $headResolved
      OutputDir = $RunDir
      Quiet     = $true
      NoiseProfile = $NoiseProfile
    }
    if ($RenderReport.IsPresent) { $params.RenderReport = $true }
    if ($UseStub.IsPresent) {
      $stubPath = Join-Path $repoRoot 'tests' 'stubs' 'Invoke-LVCompare.stub.ps1'
      if (-not (Test-Path -LiteralPath $stubPath -PathType Leaf)) { throw "Stub not found at $stubPath" }
      $params.CaptureScriptPath = $stubPath
    }

    & $driverPath @params *> $null
  } finally {
    foreach ($k in $prev.Keys) {
      $v = $prev[$k]
      if ($null -eq $v) { Remove-Item -ErrorAction SilentlyContinue -LiteralPath "Env:$k" } else { [Environment]::SetEnvironmentVariable($k, $v, 'Process') }
    }
  }

  $postSnapshot = Get-LocalDiffProcessSnapshot

  $capPath = Join-Path $RunDir 'lvcompare-capture.json'
  if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw "Capture JSON not found at $capPath" }
  $cap = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json -Depth 8

$envCli = if ($cap -and $cap.PSObject.Properties['environment'] -and $cap.environment -and $cap.environment.PSObject.Properties['cli']) { $cap.environment.cli } else { $null }

$stdoutPath = Join-Path $RunDir 'lvcli-stdout.txt'
$stderrPath = Join-Path $RunDir 'lvcli-stderr.txt'
$stdoutSnippet = Read-FileSnippet -Path $stdoutPath
$stderrSnippet = Read-FileSnippet -Path $stderrPath
$stdoutPathResolved = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { $stdoutPath } else { $null }
$stderrPathResolved = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { $stderrPath } else { $null }

$cliSkipped = if ($envCli -and $envCli.PSObject.Properties['skipped']) { [bool]$envCli.skipped } else { $false }
$skipReason = if ($envCli -and $envCli.PSObject.Properties['skipReason']) { [string]$envCli.skipReason } else { $null }

  $reportPath = if ($envCli -and $envCli.PSObject.Properties['reportPath'] -and $envCli.reportPath) { [string]$envCli.reportPath } else { $null }

$sentinelInfo = Get-SentinelSkipStatus -Vi1 $baseResolved -Vi2 $headResolved -ReportPath $reportPath -TtlSeconds $effectiveTtlUsed
if ($sentinelInfo.skipped -and -not $cliSkipped) {
  $cliSkipped = $true
  $skipReason = $sentinelInfo.reason
}

if ($Mode -eq 'git-context' -and -not $cliSkipped) {
  $cliSkipped = $true
  $skipReason = 'git-context'
}

$runInfo = [ordered]@{
  outputDir     = $RunDir
  capture       = $capPath
  stdoutPath    = $stdoutPathResolved
  stderrPath    = $stderrPathResolved
  stdoutSnippet = $stdoutSnippet
  stderrSnippet = $stderrSnippet
  exitCode      = $cap.exitCode
  seconds       = $cap.seconds
  cliSkipped    = $cliSkipped
  skipReason    = $skipReason
  mode          = $Mode
  base          = $baseResolved
  head          = $headResolved
  reportPath    = $reportPath
  sentinelPath  = $sentinelInfo.path
  preProcesses  = $preSnapshot
    postProcesses = $postSnapshot
  }

  return [pscustomobject]$runInfo
}

$summary = [ordered]@{
  schema     = 'local-diff-session@v1'
  mode       = $Mode
  base       = (Resolve-Path -LiteralPath $BaseVi).Path
  head       = (Resolve-Path -LiteralPath $HeadVi).Path
  resultsDir = $resultsRootResolved
  runs       = @()
  setupStatus = [pscustomobject]$setupStatus
}

if (-not $setupStatus.ok -and $AutoConfig.IsPresent) {
  $configScript = Join-Path $repoRoot 'tools' 'New-LVCompareConfig.ps1'
  if (Test-Path -LiteralPath $configScript -PathType Leaf) {
    Write-Host ''
    Write-Host 'Attempting to scaffold LVCompare config automatically...' -ForegroundColor Cyan
    try {
      $configParams = [ordered]@{
        OutputPath      = $localConfigPath
        NonInteractive  = $true
        Probe           = $true
      }
      if ($LabVIEWVersion) { $configParams['Version'] = $LabVIEWVersion }
      if ($LabVIEWBitness) { $configParams['Bitness'] = $LabVIEWBitness }
      if (Test-Path -LiteralPath $localConfigPath -PathType Leaf -ErrorAction SilentlyContinue) {
        $configParams['Force'] = $true
      }
      $paramPreview = $configParams.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [bool]) {
          if ($_.Value) { "-$($_.Key)" } else { '' }
        } else {
          "-$($_.Key) $($_.Value)"
        }
      } | Where-Object { $_ }
      Write-Verbose ("Auto-config params: {0}" -f ($paramPreview -join ' '))
      & $configScript @configParams | Out-Null
      $setupStatus = Invoke-SetupProbe -SuppressWarning
      if ($setupStatus.ok) {
        Write-Host 'LVCompare config auto-generated successfully.' -ForegroundColor Green
      } else {
        Write-Warning ("Auto-config completed but probe still failing: {0}" -f $setupStatus.message)
      }
    } catch {
      $setupStatus.ok = $false
      $setupStatus.message = $_.Exception.Message
      Write-Warning ("LVCompare auto-config failed: {0}" -f $setupStatus.message)
    }
  } else {
    Write-Warning ("New-LVCompareConfig.ps1 not found at {0}" -f $configScript)
  }
}

if (-not $setupStatus.ok) {
  $summaryPath = Join-Path $resultsRootResolved 'local-diff-summary.json'
  $summary.setupStatus = [pscustomobject]$setupStatus
  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
  Write-Host ''
  Write-Host '=== Local Diff Session Summary ===' -ForegroundColor Cyan
  Write-Host ("Mode     : {0}" -f $summary.mode)
  Write-Host ("Base     : {0}" -f $summary.base)
  Write-Host ("Head     : {0}" -f $summary.head)
  Write-Host ("Results  : {0}" -f $summary.resultsDir)
  Write-Host ("Setup    : {0}" -f $summary.setupStatus.message)
  Write-Host ("Hint     : run tools/New-LVCompareConfig.ps1") -ForegroundColor Yellow
  if ($Stateless.IsPresent) {
    Remove-LocalConfig -RepoRoot $repoRoot
  }
  return [pscustomobject]@{
    resultsDir   = $resultsRootResolved
    summary      = $summaryPath
    runs         = @()
    setupStatus  = [pscustomobject]$summary.setupStatus
  }
}

$run1Dir = Join-Path $resultsRootResolved 'run-01'
$r1 = Invoke-CompareRun -RunDir $run1Dir -Mode $Mode -RenderReport:$RenderReport -UseStub:$UseStub -SentinelTtlSeconds 0 -NoiseProfile $NoiseProfile
$summary.runs += $r1

if ($Mode -eq 'duplicate-window' -and $UseStub.IsPresent) {
  $touchPath = Touch-CompareCliSentinel -Vi1 $r1.base -Vi2 $r1.head -ReportPath $r1.reportPath
  if ($touchPath) { $r1.sentinelPath = $touchPath }
}

if ($Mode -eq 'duplicate-window') {
  $prevTtl = $env:COMPAREVI_CLI_SENTINEL_TTL
  try {
    $ttl = [Math]::Max(1, $SentinelTtlSeconds)
    $env:COMPAREVI_CLI_SENTINEL_TTL = [string]$ttl
    $run2Dir = Join-Path $resultsRootResolved 'run-02'
    $r2 = Invoke-CompareRun -RunDir $run2Dir -Mode 'normal' -RenderReport:$RenderReport -UseStub:$UseStub -SentinelTtlSeconds $ttl -NoiseProfile $NoiseProfile
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
  Write-Host ("Run {0}: exit={1}, skipped={2}, reason={3}, outDir={4}" -f ($i + 1), $r.exitCode, ([bool]$r.cliSkipped), ($r.skipReason ?? '-'), $r.outputDir)
}

if ($Stateless.IsPresent) {
  Remove-LocalConfig -RepoRoot $repoRoot
}

return [pscustomobject]@{
  resultsDir = $resultsRootResolved
  summary    = $summaryPath
  runs       = @($summary.runs)
  setupStatus= [pscustomobject]$setupStatus
}
