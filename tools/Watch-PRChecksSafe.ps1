param(
  [Parameter()][string]$PullRequest,
  [Parameter()][string]$Repository,
  [Parameter()][int]$IntervalSeconds = 20,
  [Parameter()][int]$HeartbeatPolls = 6,
  [Parameter()][int]$MaxPolls = 0,
  [Parameter()][int]$RunnerAdmissionQueueThresholdMinutes = 20,
  [Parameter()][switch]$RequiredOnly,
  [Parameter()][switch]$FailFast
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-GhPath {
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($gh) {
    return $gh.Source
  }

  $fallback = 'C:\Program Files\GitHub CLI\gh.exe'
  if (Test-Path -LiteralPath $fallback) {
    return $fallback
  }

  throw 'GitHub CLI (gh) was not found. Install gh or add it to PATH.'
}

function Invoke-GhJson {
  param(
    [Parameter(Mandatory)][string]$GhPath,
    [Parameter(Mandatory)][string[]]$Arguments
  )

  $output = & $GhPath @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw ("gh command failed (exit {0}): gh {1}`n{2}" -f $LASTEXITCODE, ($Arguments -join ' '), ($output -join "`n"))
  }

  if (-not $output) {
    return @()
  }

  $jsonText = ($output -join "`n").Trim()
  if ([string]::IsNullOrWhiteSpace($jsonText)) {
    return @()
  }

  $parsed = $jsonText | ConvertFrom-Json -Depth 20
  if ($parsed -is [System.Array]) {
    return $parsed
  }

  if ($null -eq $parsed) {
    return @()
  }

  return @($parsed)
}

function Invoke-GhText {
  param(
    [Parameter(Mandatory)][string]$GhPath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter()][string]$AllowedErrorPattern = ''
  )

  $output = & $GhPath @Arguments 2>&1
  $text = ($output -join "`n").Trim()
  $matchedAllowedError = $false
  if (-not [string]::IsNullOrWhiteSpace($AllowedErrorPattern) -and -not [string]::IsNullOrWhiteSpace($text)) {
    $matchedAllowedError = $text -match $AllowedErrorPattern
  }

  if ($LASTEXITCODE -ne 0 -and -not $matchedAllowedError) {
    throw ("gh command failed (exit {0}): gh {1}`n{2}" -f $LASTEXITCODE, ($Arguments -join ' '), $text)
  }

  [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = $text
    MatchedAllowedError = $matchedAllowedError
  }
}

function Resolve-PullRequestNumber {
  param(
    [Parameter(Mandatory)][string]$GhPath,
    [Parameter()][string]$ExplicitPullRequest,
    [Parameter()][string]$Repository
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitPullRequest)) {
    return $ExplicitPullRequest
  }

  $args = @('pr', 'view', '--json', 'number', '--jq', '.number')
  if (-not [string]::IsNullOrWhiteSpace($Repository)) {
    $args += @('--repo', $Repository)
  }

  $number = & $GhPath @args 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($number)) {
    throw 'Unable to determine pull request number. Pass -PullRequest <number>.'
  }

  return $number.Trim()
}

function Get-PrChecksSnapshot {
  param(
    [Parameter(Mandatory)][string]$GhPath,
    [Parameter(Mandatory)][string]$PullRequest,
    [Parameter()][string]$Repository,
    [Parameter()][switch]$RequiredOnly
  )

  $args = @('pr', 'checks', $PullRequest, '--json', 'name,state,workflow,bucket,link')
  if ($RequiredOnly) {
    $args += '--required'
  }
  if (-not [string]::IsNullOrWhiteSpace($Repository)) {
    $args += @('--repo', $Repository)
  }

  $response = Invoke-GhText -GhPath $GhPath -Arguments $args -AllowedErrorPattern 'no checks reported'
  if ($response.ExitCode -ne 0 -and $response.MatchedAllowedError) {
    return [pscustomobject]@{
      NoChecksReported = $true
      Checks = @()
    }
  }

  $checks = @()
  if (-not [string]::IsNullOrWhiteSpace($response.Output)) {
    $parsed = $response.Output | ConvertFrom-Json -Depth 20
    if ($parsed -is [System.Array]) {
      $checks = @($parsed)
    } elseif ($null -ne $parsed) {
      $checks = @($parsed)
    }
  }

  return [pscustomobject]@{
    NoChecksReported = $false
    Checks = @($checks | ForEach-Object {
        [pscustomobject]@{
          Workflow = [string]$_.workflow
          Name = [string]$_.name
          Bucket = [string]$_.bucket
          State = [string]$_.state
          Link = [string]$_.link
        }
      })
  }
}

function Get-PollDelayMilliseconds {
  param([Parameter(Mandatory)][int]$IntervalSeconds)

  $override = $env:WATCH_PR_CHECKS_POLL_DELAY_MILLISECONDS
  if (-not [string]::IsNullOrWhiteSpace($override)) {
    $parsedOverride = 0
    if ([int]::TryParse($override, [ref]$parsedOverride) -and $parsedOverride -ge 0) {
      return $parsedOverride
    }
  }

  return ($IntervalSeconds * 1000)
}

function Resolve-JobDescriptor {
  param(
    [Parameter()][string]$Repository,
    [Parameter()][string]$Link
  )

  if ([string]::IsNullOrWhiteSpace($Link)) {
    return $null
  }

  if ($Link -match '^https://github\.com/(?<repo>[^/]+/[^/]+)/actions/runs/(?<run>\d+)/job/(?<job>\d+)$') {
    return [pscustomobject]@{
      Repository = if (-not [string]::IsNullOrWhiteSpace($Repository)) { $Repository } else { $Matches.repo }
      RunId = [int64]$Matches.run
      JobId = [int64]$Matches.job
    }
  }

  return $null
}

function Get-QueuedSelfHostedAdmissionBlockers {
  param(
    [Parameter(Mandatory)][string]$GhPath,
    [Parameter(Mandatory)][System.Collections.IEnumerable]$Checks,
    [Parameter()][string]$Repository,
    [Parameter(Mandatory)][int]$ThresholdMinutes
  )

  $now = [DateTimeOffset]::UtcNow
  $runnerInventoryCache = @{}
  $blockers = @()
  foreach ($check in @($Checks | Where-Object { $_.Bucket -eq 'pending' -and $_.State -eq 'QUEUED' })) {
    $descriptor = Resolve-JobDescriptor -Repository $Repository -Link $check.Link
    if ($null -eq $descriptor) {
      continue
    }

    $jobResponse = Invoke-GhJson -GhPath $GhPath -Arguments @('api', "repos/$($descriptor.Repository)/actions/jobs/$($descriptor.JobId)")
    $job = @($jobResponse)[0]
    if ($null -eq $job) {
      continue
    }

    $labels = @($job.labels | ForEach-Object { [string]$_ })
    $isSelfHosted = $labels -contains 'self-hosted'
    $runnerId = 0
    if ($null -ne $job.runner_id) {
      $runnerId = [int64]$job.runner_id
    }
    $runnerAssigned = ($runnerId -gt 0) -or -not [string]::IsNullOrWhiteSpace([string]$job.runner_name)
    $queuedAt = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$job.started_at)) {
      $queuedAt = [DateTimeOffset]::Parse([string]$job.started_at)
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$job.created_at)) {
      $queuedAt = [DateTimeOffset]::Parse([string]$job.created_at)
    }

    $queueAgeMinutes = $null
    if ($null -ne $queuedAt) {
      $queueAgeMinutes = [int][math]::Floor(($now - $queuedAt).TotalMinutes)
      if ($queueAgeMinutes -lt 0) {
        $queueAgeMinutes = $null
      }
    }

    $runnerInventory = $null
    if (-not $runnerInventoryCache.ContainsKey($descriptor.Repository)) {
      try {
        $runnerInventoryResponse = Invoke-GhJson -GhPath $GhPath -Arguments @('api', "repos/$($descriptor.Repository)/actions/runners")
        $runnerInventoryPayload = @($runnerInventoryResponse)[0]
        $runnerInventory = [pscustomobject]@{
          Accessible = $true
          TotalCount = if ($null -ne $runnerInventoryPayload.total_count) { [int]$runnerInventoryPayload.total_count } else { @($runnerInventoryPayload.runners).Count }
          Error = $null
        }
      } catch {
        $runnerInventory = [pscustomobject]@{
          Accessible = $false
          TotalCount = $null
          Error = $_.Exception.Message
        }
      }
      $runnerInventoryCache[$descriptor.Repository] = $runnerInventory
    } else {
      $runnerInventory = $runnerInventoryCache[$descriptor.Repository]
    }

    $queueThresholdMet = $null -ne $queueAgeMinutes -and $queueAgeMinutes -ge $ThresholdMinutes
    $repoHasNoRunners = $runnerInventory.Accessible -and $runnerInventory.TotalCount -eq 0
    if ($isSelfHosted -and -not $runnerAssigned -and [string]$job.status -eq 'queued' -and ($queueThresholdMet -or $repoHasNoRunners)) {
      $blockers += [pscustomobject]@{
        Repository = $descriptor.Repository
        Workflow = [string]$check.Workflow
        Name = [string]$check.Name
        RunId = [int64]$descriptor.RunId
        JobId = [int64]$descriptor.JobId
        QueueAgeMinutes = $queueAgeMinutes
        Status = [string]$job.status
        Labels = $labels
        RunnerId = $runnerId
        RunnerName = [string]$job.runner_name
        RunnerGroupId = if ($null -ne $job.runner_group_id) { [int64]$job.runner_group_id } else { 0 }
        RunnerGroupName = [string]$job.runner_group_name
        RepositoryRunnerCount = $runnerInventory.TotalCount
        RepositoryRunnerInventoryAccessible = $runnerInventory.Accessible
        ClassificationReason = if ($repoHasNoRunners) { 'repo-runners-zero' } else { 'queue-age-threshold' }
      }
    }
  }

  return @($blockers)
}

function Get-BucketCount {
  param(
    [Parameter(Mandatory)][System.Collections.IEnumerable]$Checks,
    [Parameter(Mandatory)][string]$Bucket
  )

  $items = @($Checks)
  return @($items | Where-Object { $_.Bucket -eq $Bucket }).Count
}

function Get-CheckMap {
  param([Parameter(Mandatory)][System.Collections.IEnumerable]$Checks)
  $map = @{}
  foreach ($check in $Checks) {
    $key = "{0}/{1}" -f $check.Workflow, $check.Name
    $map[$key] = [string]$check.Bucket
  }
  return $map
}

function Write-SummaryLine {
  param(
    [Parameter(Mandatory)][int]$Iteration,
    [Parameter(Mandatory)][System.Collections.IEnumerable]$Checks,
    [Parameter()][switch]$NoChecksReported
  )

  if ($NoChecksReported) {
    $stamp = (Get-Date).ToString('u')
    Write-Host ("[{0}] poll={1} checks=none-yet" -f $stamp, $Iteration)
    return
  }

  $items = @($Checks)
  $pass = Get-BucketCount -Checks $items -Bucket 'pass'
  $fail = Get-BucketCount -Checks $items -Bucket 'fail'
  $pending = Get-BucketCount -Checks $items -Bucket 'pending'
  $skipping = Get-BucketCount -Checks $items -Bucket 'skipping'
  $cancel = Get-BucketCount -Checks $items -Bucket 'cancel'
  $stamp = (Get-Date).ToString('u')

  Write-Host ("[{0}] poll={1} pass={2} fail={3} pending={4} skip={5} cancel={6}" -f $stamp, $Iteration, $pass, $fail, $pending, $skipping, $cancel)
}

function Write-RunnerAdmissionBlockerSummary {
  param([Parameter(Mandatory)][System.Collections.IEnumerable]$Blockers)

  $items = @(
    $Blockers |
      Sort-Object -Property @(
        @{ Expression = 'QueueAgeMinutes'; Descending = $true },
        @{ Expression = 'Workflow'; Descending = $false },
        @{ Expression = 'Name'; Descending = $false }
      )
  )
  Write-Host ("Blocked: self-hosted runner admission starvation detected on {0} queued check(s)." -f $items.Count)
  foreach ($item in $items) {
    $queuedLabel = if ($null -ne $item.QueueAgeMinutes) { '{0}m' -f $item.QueueAgeMinutes } else { 'unknown' }
    $repoRunnerCount = if ($null -ne $item.RepositoryRunnerCount) { $item.RepositoryRunnerCount } else { 'unknown' }
    Write-Host ("  - {0}/{1}: queued={2} repo={3} run={4} job={5} labels={6} runner_id={7} repo_runners={8} reason={9}" -f $item.Workflow, $item.Name, $queuedLabel, $item.Repository, $item.RunId, $item.JobId, ($item.Labels -join ','), $item.RunnerId, $repoRunnerCount, $item.ClassificationReason)
  }
}

if ($IntervalSeconds -lt 5) {
  throw '-IntervalSeconds must be >= 5 to avoid excessive polling.'
}
if ($HeartbeatPolls -lt 1) {
  throw '-HeartbeatPolls must be >= 1.'
}
if ($MaxPolls -lt 0) {
  throw '-MaxPolls must be >= 0.'
}
if ($RunnerAdmissionQueueThresholdMinutes -lt 1) {
  throw '-RunnerAdmissionQueueThresholdMinutes must be >= 1.'
}

$ghPath = Resolve-GhPath
$targetPr = Resolve-PullRequestNumber -GhPath $ghPath -ExplicitPullRequest $PullRequest -Repository $Repository
$pollDelayMilliseconds = Get-PollDelayMilliseconds -IntervalSeconds $IntervalSeconds

Write-Host ("Monitoring PR #{0} with snapshot polling (interval={1}s, requiredOnly={2}, failFast={3})." -f $targetPr, $IntervalSeconds, [bool]$RequiredOnly, [bool]$FailFast)
Write-Host 'Using gh pr checks --json snapshots (no --watch).'

$previousMap = $null
$poll = 0

while ($true) {
  $poll += 1
  $snapshot = Get-PrChecksSnapshot -GhPath $ghPath -PullRequest $targetPr -Repository $Repository -RequiredOnly:$RequiredOnly
  $checks = @($snapshot.Checks)
  $currentMap = Get-CheckMap -Checks $checks

  if ($null -eq $previousMap) {
    Write-SummaryLine -Iteration $poll -Checks $checks -NoChecksReported:$snapshot.NoChecksReported
  } else {
    $changed = @()
    foreach ($key in $currentMap.Keys) {
      if (-not $previousMap.ContainsKey($key) -or $previousMap[$key] -ne $currentMap[$key]) {
        $changed += [pscustomobject]@{ Key = $key; Bucket = $currentMap[$key] }
      }
    }
    foreach ($key in $previousMap.Keys) {
      if (-not $currentMap.ContainsKey($key)) {
        $changed += [pscustomobject]@{ Key = $key; Bucket = 'removed' }
      }
    }

    if ($changed.Count -gt 0) {
      Write-SummaryLine -Iteration $poll -Checks $checks -NoChecksReported:$snapshot.NoChecksReported
      foreach ($entry in ($changed | Sort-Object Key | Select-Object -First 12)) {
        Write-Host ("  - {0} => {1}" -f $entry.Key, $entry.Bucket)
      }
      if ($changed.Count -gt 12) {
        Write-Host ("  - ... {0} additional change(s)" -f ($changed.Count - 12))
      }
    } elseif (($poll % $HeartbeatPolls) -eq 0) {
      Write-SummaryLine -Iteration $poll -Checks $checks -NoChecksReported:$snapshot.NoChecksReported
      if ($snapshot.NoChecksReported) {
        Write-Host '  (still waiting for initial check publication)'
      } else {
        Write-Host '  (no state changes since last poll)'
      }
    }
  }

  if ($snapshot.NoChecksReported) {
    if ($MaxPolls -gt 0 -and $poll -ge $MaxPolls) {
      Write-Host ("Reached MaxPolls={0} with no checks reported yet." -f $MaxPolls)
      exit 8
    }

    $previousMap = $currentMap
    Start-Sleep -Milliseconds $pollDelayMilliseconds
    continue
  }

  $failCount = Get-BucketCount -Checks $checks -Bucket 'fail'
  $pendingCount = Get-BucketCount -Checks $checks -Bucket 'pending'
  if ($pendingCount -gt 0) {
    $runnerAdmissionBlockers = @(Get-QueuedSelfHostedAdmissionBlockers -GhPath $ghPath -Checks $checks -Repository $Repository -ThresholdMinutes $RunnerAdmissionQueueThresholdMinutes)
    if ($runnerAdmissionBlockers.Count -gt 0) {
      Write-RunnerAdmissionBlockerSummary -Blockers $runnerAdmissionBlockers
      exit 9
    }
  }

  if ($FailFast -and $failCount -gt 0) {
    Write-Host 'Fail-fast: at least one check failed.'
    exit 1
  }

  if ($pendingCount -eq 0) {
    if ($failCount -gt 0) {
      Write-Host 'Completed with failures.'
      exit 1
    }
    Write-Host 'All tracked checks completed successfully.'
    exit 0
  }

  if ($MaxPolls -gt 0 -and $poll -ge $MaxPolls) {
    Write-Host ("Reached MaxPolls={0} with pending checks still present." -f $MaxPolls)
    exit 8
  }

  $previousMap = $currentMap
  Start-Sleep -Milliseconds $pollDelayMilliseconds
}
