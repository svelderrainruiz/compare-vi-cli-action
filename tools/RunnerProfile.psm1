Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RunnerProfileCache = $null
$script:RunnerLabelsCache = $null

function Get-RunnerProfile {
  [CmdletBinding()]
  param(
    [switch]$ForceRefresh
  )

  if (-not $ForceRefresh -and $script:RunnerProfileCache) {
    return $script:RunnerProfileCache
  }

  $profile = [ordered]@{}

  $envMap = @{
    name         = 'RUNNER_NAME'
    os           = 'RUNNER_OS'
    arch         = 'RUNNER_ARCH'
    environment  = 'RUNNER_ENVIRONMENT'
    trackingId   = 'RUNNER_TRACKING_ID'
    imageOS      = 'ImageOS'
    imageVersion = 'ImageVersion'
  }

  foreach ($key in $envMap.Keys) {
    $value = Get-EnvironmentValue -Name $envMap[$key]
    if ($value) { $profile[$key] = $value }
  }

  $profile['machine'] = [System.Environment]::MachineName

  $labels = Get-RunnerLabels -ForceRefresh:$ForceRefresh
  if ($labels -and $labels.Count -gt 0) {
    $profile['labels'] = $labels
  }

  $script:RunnerProfileCache = [pscustomobject]$profile
  return $script:RunnerProfileCache
}

function Get-RunnerLabels {
  [CmdletBinding()]
  param(
    [switch]$ForceRefresh
  )

  if (-not $ForceRefresh -and $script:RunnerLabelsCache) {
    return $script:RunnerLabelsCache
  }

  $labels = @()

  $envLabels = Get-EnvironmentValue -Name 'RUNNER_LABELS'
  if ($envLabels) {
    $labels = Parse-Labels -Raw $envLabels
  }

  if ($labels.Count -eq 0) {
    $labels = Get-RunnerLabelsFromApi
  }

  $script:RunnerLabelsCache = $labels
  return $labels
}

function Get-RunnerLabelsFromApi {
  [CmdletBinding()]
  param()

  $repo = Get-EnvironmentValue -Name 'GITHUB_REPOSITORY'
  $runId = Get-EnvironmentValue -Name 'GITHUB_RUN_ID'
  if (-not $repo -or -not $runId) { return @() }

  $jobs = Invoke-RunnerJobsApi -Repository $repo -RunId $runId
  if (-not $jobs -or $jobs.Count -eq 0) { return @() }

  $runnerName = Get-EnvironmentValue -Name 'RUNNER_NAME'
  $jobName = Get-EnvironmentValue -Name 'GITHUB_JOB'
  $runAttempt = Get-EnvironmentValue -Name 'GITHUB_RUN_ATTEMPT'

  $candidates = @()
  if ($runnerName) {
    $candidates = @($jobs | Where-Object { $_.runner_name -and $_.runner_name -eq $runnerName })
  }

  if ($candidates.Count -eq 0 -and $jobName) {
    $candidates = @($jobs | Where-Object { $_.name -eq $jobName })
  }

  if ($candidates.Count -gt 1 -and $runAttempt) {
    $attempt = 0
    if ([int]::TryParse($runAttempt, [ref]$attempt)) {
      $filtered = @($candidates | Where-Object { $_.run_attempt -eq $attempt })
      if ($filtered.Count -gt 0) { $candidates = $filtered }
    }
  }

  if ($candidates.Count -eq 0) {
    $candidates = @(
      $jobs |
        Where-Object { $_.status -and $_.status -ne 'queued' } |
        Sort-Object started_at |
        Select-Object -Last 1
    )
  } else {
    $candidates = @(
      $candidates |
        Sort-Object started_at |
        Select-Object -Last 1
    )
  }

  if ($candidates.Count -eq 0) { return @() }
  $labels = $candidates[0].labels
  if (-not $labels) { return @() }

  return @($labels | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique)
}

function Invoke-RunnerJobsApi {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$RunId
  )

  $endpoint = "repos/$Repository/actions/runs/$RunId/jobs?per_page=100"

  $gh = $null
  try { $gh = Get-Command -Name gh -ErrorAction Stop } catch {}
  if ($gh) {
    try {
      $args = @('api', $endpoint, '--header', 'Accept: application/vnd.github+json')
      $raw = & $gh.Source @args 2>$null
      if ($LASTEXITCODE -eq 0 -and $raw) {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -and $parsed.PSObject.Properties.Name -contains 'jobs') {
          return @($parsed.jobs)
        }
      }
    } catch {}
  }

  $token = Get-EnvironmentValue -Name 'GH_TOKEN'
  if (-not $token) { $token = Get-EnvironmentValue -Name 'GITHUB_TOKEN' }
  if (-not $token) { return @() }

  $uri = "https://api.github.com/$endpoint"
  try {
    $headers = @{
      'Accept'       = 'application/vnd.github+json'
      'Authorization'= "Bearer $token"
      'User-Agent'   = 'RunnerProfile.psm1'
    }
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    if ($response -and $response.PSObject.Properties.Name -contains 'jobs') {
      return @($response.jobs)
    }
  } catch {}

  return @()
}

function Get-EnvironmentValue {
  param([string]$Name)
  if (-not $Name) { return $null }
  try {
    $value = [System.Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $value) { return $null }
    $string = "$value"
    if ([string]::IsNullOrWhiteSpace($string)) { return $null }
    return $string.Trim()
  } catch {
    return $null
  }
}

function Parse-Labels {
  param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }
  $parts = $Raw -split '[,\s]+' | Where-Object { $_ -and $_ -ne '' }
  return @($parts | Select-Object -Unique)
}

Export-ModuleMember -Function Get-RunnerProfile,Get-RunnerLabels
