#Requires -Version 7.0
[CmdletBinding()]
param(
  [object[]]$BufferSeconds = @(5, 10, 15),
  [int]$MinBufferSeconds,
  [int]$MaxBufferSeconds,
  [int]$BufferStepSeconds = 5,
  [int]$RunsPerBuffer = 3,
  [switch]$RenderReport,
  [string]$ResultsDir = 'tests/results/_labview_buffer_calibration',
  [int]$MaxAllowedSeconds = 60,
  [int]$CloseRetries = 1,
  [int]$CloseRetryDelaySeconds = 2,
  [string]$LabVIEWExePath,
  [switch]$KeepResults,
  [switch]$Quiet,
  [switch]$CaptureProcessSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($BufferStepSeconds -le 0) { throw 'BufferStepSeconds must be greater than zero.' }
if ($MaxAllowedSeconds -le 0) { throw 'MaxAllowedSeconds must be greater than zero.' }
if ($CloseRetries -lt 0) { throw 'CloseRetries must not be negative.' }
if ($CloseRetryDelaySeconds -lt 0) { throw 'CloseRetryDelaySeconds must not be negative.' }
if ($RunsPerBuffer -le 0) { throw 'RunsPerBuffer must be greater than zero.' }

$repoRoot = (Resolve-Path '.').Path
$invokeScript = Join-Path $repoRoot 'tools' 'Invoke-LVCompare.ps1'
if (-not (Test-Path -LiteralPath $invokeScript -PathType Leaf)) {
  throw "Invoke-LVCompare.ps1 not found at $invokeScript"
}
$closeScript = Join-Path $repoRoot 'tools' 'Close-LabVIEW.ps1'
$agentWaitScript = Join-Path $repoRoot 'tools' 'Agent-Wait.ps1'

$hasAgentWait = $false
if (Test-Path -LiteralPath $agentWaitScript -PathType Leaf) {
  try {
    . $agentWaitScript
    if (Get-Command -Name 'Start-AgentWait' -ErrorAction SilentlyContinue) {
      $hasAgentWait = $true
    }
  } catch {
    Write-Warning ("Calibrate-LabVIEWBuffer: unable to load Agent-Wait helpers: {0}" -f $_.Exception.Message)
  }
}

function Convert-BufferValues {
  param(
    [object[]]$Values,
    [int]$Min,
    [int]$Max,
    [int]$Step,
    [int]$MaxAllowed
  )

  $candidateList = New-Object System.Collections.Generic.List[int]

  if ($Values) {
    foreach ($value in $Values) {
      if ($null -eq $value) { continue }
      switch ($value) {
        { $_ -is [int] -or $_ -is [long] } {
          $candidateList.Add([int]$_)
        }
        { $_ -is [double] } {
          $candidateList.Add([int][Math]::Round($_))
        }
        { $_ -is [string] } {
          $matches = [regex]::Matches($_, '\d+')
          foreach ($m in $matches) { $candidateList.Add([int]$m.Value) }
        }
        default { }
      }
    }
  }

  if ($Min -gt 0 -and $Max -gt 0 -and $Max -ge $Min) {
    for ($v = [int]$Min; $v -le $Max; $v += [int]$Step) {
      $candidateList.Add($v)
    }
  }

  $filtered = @()
  foreach ($value in ($candidateList | Sort-Object -Unique)) {
    if ($value -le 0) {
      Write-Warning ("Calibration skipped non-positive buffer value '{0}'." -f $value)
      continue
    }
    if ($value -gt $MaxAllowed) {
      Write-Warning ("Calibration skipped buffer value '{0}'s because it exceeds MaxAllowedSeconds ({1}s)." -f $value, $MaxAllowed)
      continue
    }
    $filtered += [int]$value
  }

  return @($filtered | Sort-Object -Unique)
}

$bufferValues = Convert-BufferValues -Values $BufferSeconds -Min $MinBufferSeconds -Max $MaxBufferSeconds -Step $BufferStepSeconds -MaxAllowed $MaxAllowedSeconds
if (-not $bufferValues -or (($bufferValues | Measure-Object).Count -eq 0)) {
  throw 'No valid buffer durations supplied.'
}

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$summaryPath = Join-Path $ResultsDir 'calibration-summary.json'

$summary = [ordered]@{
  schema        = 'labview-buffer-calibration/v1'
  generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
  runsPerBuffer = $RunsPerBuffer
  resultsDir    = (Resolve-Path $ResultsDir).Path
  parameters    = [ordered]@{
    bufferList             = $BufferSeconds
    minBufferSeconds       = $MinBufferSeconds
    maxBufferSeconds       = $MaxBufferSeconds
    bufferStepSeconds      = $BufferStepSeconds
    maxAllowedSeconds      = $MaxAllowedSeconds
    closeRetries           = $CloseRetries
    closeRetryDelaySeconds = $CloseRetryDelaySeconds
    labviewExePath         = $LabVIEWExePath
    keepResults            = [bool]$KeepResults
    captureProcessSnapshot = [bool]$CaptureProcessSnapshot
  }
  results       = @()
}

function Get-ProcessSnapshot {
  param(
    [string[]]$Names = @('pwsh','LabVIEW','LVCompare')
  )
  $snapshot = New-Object System.Collections.Generic.List[object]
  foreach ($name in $Names) {
    try {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    } catch {
      $procs = @()
    }
    foreach ($proc in $procs) {
      $start = $null
      try { $start = $proc.StartTime.ToUniversalTime().ToString('o') } catch { $start = $null }
      $snapshot.Add([ordered]@{
        id      = $proc.Id
        name    = $proc.ProcessName
        startUtc= $start
        cpu     = $proc.CPU
        company = $proc.Company
      })
    }
  }
  return @($snapshot | Sort-Object -Property id)
}

function Invoke-LabVIEWCleanup {
  param(
    [int]$Seconds,
    [string]$WaitId,
    [int]$Retries,
    [int]$RetryDelaySeconds,
    [string]$LabVIEWExePath,
    [switch]$HasAgentWait
  )

  $waitStarted = $false
  if ($HasAgentWait) {
    try {
      Start-AgentWait -Reason 'buffer calibration' -ExpectedSeconds $Seconds -Id $WaitId | Out-Null
      $waitStarted = $true
    } catch {
      Write-Warning ("Calibrate-LabVIEWBuffer: Start-AgentWait failed: {0}" -f $_.Exception.Message)
    }
  }

  if ($Seconds -gt 0) { Start-Sleep -Seconds $Seconds }

  if ($waitStarted) {
    try { End-AgentWait -Id $WaitId | Out-Null } catch {}
  }

  $initialPids = @()
  try { $initialPids = @(Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) } catch {}

  $closeAttempts = @()
  $closeExit = $null
  if (Test-Path -LiteralPath $closeScript -PathType Leaf) {
    $attemptsToRun = [Math]::Max(0, $Retries) + 1
    for ($attempt = 0; $attempt -lt $attemptsToRun; $attempt++) {
      $args = @('-NoLogo','-NoProfile','-File',$closeScript)
      if ($LabVIEWExePath) { $args += @('-LabVIEWExePath', $LabVIEWExePath) }
      $output = @()
      try {
        $output = & pwsh @args 2>&1
        $closeExit = $LASTEXITCODE
      } catch {
        $output = @($_.Exception.Message)
        $closeExit = -1
      }
      $closeAttempts += [ordered]@{
        attempt = $attempt + 1
        exitCode = $closeExit
        output   = @($output)
      }
      if ($closeExit -eq 0) { break }
      if ($attempt -lt ($attemptsToRun - 1) -and $RetryDelaySeconds -gt 0) {
        Start-Sleep -Seconds $RetryDelaySeconds
      }
    }
  } else {
    Write-Warning ("Calibrate-LabVIEWBuffer: Close-LabVIEW.ps1 not found at {0}; skipping graceful shutdown." -f $closeScript)
  }

  $labviewPidList = @()
  try { $labviewPidList = @(Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) } catch {}

  $forced = $false
  $forceError = $null
  if ((@($labviewPidList) | Measure-Object).Count -gt 0) {
    try {
      Stop-Process -Id $labviewPidList -Force -ErrorAction Stop
      $forced = $true
      Start-Sleep -Milliseconds 250
      $labviewPidList = @(Get-Process -Name 'LabVIEW' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    } catch {
      $forceError = $_.Exception.Message
      Write-Warning ("Calibrate-LabVIEWBuffer: Stop-Process failed: {0}" -f $forceError)
    }
  }

  [pscustomobject]@{
    waitSeconds    = $Seconds
    initialPids    = $initialPids
    closeAttempts  = $closeAttempts
    forced         = $forced
    forceError     = $forceError
    remainingPids  = $labviewPidList
  }
}

foreach ($buffer in $bufferValues) {
  $bufferResult = [ordered]@{
    bufferSeconds = $buffer
    runs          = @()
    successCount  = 0
  }

  for ($i = 1; $i -le $RunsPerBuffer; $i++) {
    $runId = ("buffer-{0}-run-{1}" -f $buffer, $i)
    $outputDir = Join-Path $ResultsDir ("buffer-{0}\run-{1}" -f $buffer, $i)
    if (Test-Path -LiteralPath $outputDir) {
      try { Remove-Item -LiteralPath $outputDir -Recurse -Force } catch {}
    }
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    $processPre = @()
    if ($CaptureProcessSnapshot) {
      $processPre = Get-ProcessSnapshot
    }

    $invokeArgs = @(
      '-NoLogo','-NoProfile',
      '-File', $invokeScript,
      '-BaseVi', (Join-Path $repoRoot 'VI1.vi'),
      '-HeadVi', (Join-Path $repoRoot 'VI2.vi'),
      '-OutputDir', $outputDir,
      '-NoiseProfile', 'full',
      '-LeakCheck',
      '-LeakGraceSeconds', '0'
    )
    if ($RenderReport) { $invokeArgs += '-RenderReport' }
    if ($Quiet) { $invokeArgs += '-Quiet' }

    & pwsh @invokeArgs | Out-Null
    $invokeExit = $LASTEXITCODE

    $cleanup = Invoke-LabVIEWCleanup -Seconds $buffer -WaitId $runId -Retries $CloseRetries -RetryDelaySeconds $CloseRetryDelaySeconds -LabVIEWExePath $LabVIEWExePath -HasAgentWait:$hasAgentWait

    $remainingCount = ($cleanup.remainingPids | Measure-Object).Count
    $success = ($remainingCount -eq 0)
    if (-not $success) {
      $remainingList = @($cleanup.remainingPids)
      Write-Warning ("Calibration buffer {0}s run {1}: LabVIEW.exe still running (PID(s) {2})." -f $buffer, $i, ($remainingList -join ','))
    }

    if ($success) { $bufferResult.successCount++ }

    $runRecord = [ordered]@{
      run            = $i
      invokeExitCode = $invokeExit
      cleanup        = $cleanup
      success        = $success
      compareLeak    = (Join-Path $outputDir 'compare-leak.json')
    }

    if ($CaptureProcessSnapshot) {
      $processPost = Get-ProcessSnapshot
      $preIds = @($processPre.Id)
      $newProcesses = @()
      foreach ($proc in $processPost) {
        if (-not ($preIds -contains $proc.Id)) {
          $newProcesses += $proc
        }
      }
      $runRecord.processSnapshot = [ordered]@{
        pre  = $processPre
        post = $processPost
        new  = $newProcesses
      }
      if ($newProcesses.Count -gt 0 -and -not $Quiet) {
        Write-Warning ("Calibration buffer {0}s run {1}: new processes detected: {2}" -f $buffer, $i, ($newProcesses | ForEach-Object { "{0}:{1}" -f $_.Name, $_.Id } -join '; '))
      }
    }

    $bufferResult.runs += $runRecord

    if ($success -and -not $KeepResults) {
      try { Remove-Item -LiteralPath $outputDir -Recurse -Force } catch {}
    }
  }

  $summary.results += [pscustomobject]$bufferResult
}

$summary | ConvertTo-Json -Depth 12 | Out-File -FilePath $summaryPath -Encoding utf8

if (-not $Quiet) {
  Write-Host "LabVIEW buffer calibration complete. Summary written to $summaryPath"
  Write-Host ""
  Write-Host "Buffer Calibration Results:"
  Write-Host "Buffer(s) | Success | Forced | Remaining PIDs"
  Write-Host "----------+---------+--------+----------------"
  foreach ($result in ($summary.results | Sort-Object bufferSeconds)) {
    $forcedCount = ($result.runs | Where-Object { $_.cleanup.forced } | Measure-Object).Count
    $remaining = @()
    foreach ($run in $result.runs) {
      $runRemaining = @($run.cleanup.remainingPids)
      if (($runRemaining | Measure-Object).Count -gt 0) {
        $remaining += ("{0}:{1}" -f $run.run, ($runRemaining -join ','))
      }
    }
    $remainingText = if ($remaining) { $remaining -join '; ' } else { '-' }
    $runsCount = ($result.runs | Measure-Object).Count
    $successText = ("{0}/{1}" -f $result.successCount, $runsCount)
    Write-Host ("{0,8}s | {1,7} | {2,6} | {3}" -f $result.bufferSeconds, $successText, $forcedCount, $remainingText)
  }
}
