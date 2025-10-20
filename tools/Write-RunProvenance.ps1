<#
.SYNOPSIS
  Write run provenance (with fallbacks) to results/provenance.json and optionally append to the job summary.

.DESCRIPTION
  Reads GitHub Actions environment variables (and event payload when available) to populate:
  - schema, schemaVersion, generatedAtUtc
  - runId, runAttempt, workflow, eventName, repository
  - ref (full), refName, headRef (fallback to refName), baseRef, headSha, prNumber (when PR event)
  - branch (alias of refName)
  - origin_kind, origin_pr, origin_comment_id/url, origin_author
  - sample_id, include_integration, strategy

  Writes JSON to <ResultsDir>/provenance.json and, when GITHUB_STEP_SUMMARY is set, appends a concise
  "Run Provenance" block.
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'tests/results',
[string]$FileName = 'provenance.json',
[switch]$AppendStepSummary
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path -Parent $PSCommandPath
$runnerModulePath = Join-Path $toolRoot 'RunnerProfile.psm1'
if (Test-Path -LiteralPath $runnerModulePath -PathType Leaf) {
  try { Import-Module $runnerModulePath -Force } catch { Write-Verbose "RunnerProfile module import failed: $_" }
}

if (-not (Test-Path -LiteralPath $ResultsDir -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
}
$outPath = Join-Path $ResultsDir $FileName

# Gather env with safe defaults
$ref        = $env:GITHUB_REF
$refName    = if ($env:GITHUB_REF_NAME) { $env:GITHUB_REF_NAME } elseif ($ref -match 'refs/heads/(.+)$') { $Matches[1] } else { '' }
$eventName  = $env:GITHUB_EVENT_NAME
$repo       = $env:GITHUB_REPOSITORY
$runId      = $env:GITHUB_RUN_ID
$runAttempt = $env:GITHUB_RUN_ATTEMPT
$workflow   = $env:GITHUB_WORKFLOW

$headRefFromEnv = $env:GITHUB_HEAD_REF
if ($eventName -eq 'workflow_dispatch') {
  if ([string]::IsNullOrWhiteSpace($headRefFromEnv)) {
    $headRef = $refName
  } else {
    $headRef = $headRefFromEnv
  }
} else {
  $headRef = if ($headRefFromEnv) { $headRefFromEnv } else { $refName }
}
$baseRef    = if ($env:GITHUB_BASE_REF) { $env:GITHUB_BASE_REF } else { '' }
$headSha    = $env:GITHUB_SHA

# Best-effort runner profile (includes labels when available)
$runnerProfile = $null
try {
  if (Get-Command -Name Get-RunnerProfile -ErrorAction SilentlyContinue) {
    $runnerProfile = Get-RunnerProfile
  }
} catch { }

# Try to read PR number from event payload when available
$prNumber = $null
try {
  if ($env:GITHUB_EVENT_PATH -and (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH -PathType Leaf)) {
    $evt = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($evt.pull_request) {
      $prNumber = $evt.pull_request.number
      # Prefer PR refs if provided
      if ($evt.pull_request.head.ref) { $headRef = "$($evt.pull_request.head.ref)" }
      if ($evt.pull_request.base.ref) { $baseRef = "$($evt.pull_request.base.ref)" }
    }
  }
} catch { }

$prov = [ordered]@{
  schema              = 'run-provenance/v1'
  schemaVersion       = '1.0.0'
  generatedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
  repository          = $repo
  workflow            = $workflow
  eventName           = $eventName
  runId               = $runId
  runAttempt          = $runAttempt
  ref                 = $ref
  refName             = $refName
  branch              = $refName
  headRef             = $headRef
  baseRef             = $baseRef
  headSha             = $headSha
  runner              = [ordered]@{
    name          = $env:RUNNER_NAME
    os            = $env:RUNNER_OS
    arch          = $env:RUNNER_ARCH
    job           = $env:GITHUB_JOB
    machine       = [System.Environment]::MachineName
    trackingId    = $env:RUNNER_TRACKING_ID
    imageOS       = $env:ImageOS
    imageVersion  = $env:ImageVersion
  }
}

if ($runnerProfile) {
  foreach ($property in @('name','os','arch','environment','machine','trackingId','imageOS','imageVersion')) {
    if ($runnerProfile.PSObject.Properties.Name -contains $property) {
      $value = $runnerProfile.$property
      if ($null -ne $value -and "$value" -ne '') {
        $prov.runner[$property] = $value
      }
    }
  }
  if ($runnerProfile.PSObject.Properties.Name -contains 'labels') {
    $labels = $runnerProfile.labels
    if ($labels -and $labels.Count -gt 0) {
      $prov.runner['labels'] = @($labels | Where-Object { $_ -and $_ -ne '' })
    }
  }
}

if (-not $prov.runner.job -and $env:GITHUB_JOB) {
  $prov.runner['job'] = $env:GITHUB_JOB
}

if ($prNumber) { $prov['prNumber'] = $prNumber }

# Optional origin and inputs (populated by workflow env)
foreach($k in 'EV_ORIGIN_KIND','EV_ORIGIN_PR','EV_ORIGIN_COMMENT_ID','EV_ORIGIN_COMMENT_URL','EV_ORIGIN_AUTHOR','EV_SAMPLE_ID','EV_INCLUDE_INTEGRATION','EV_STRATEGY'){
  $v = Get-Item -Path Env:$k -ErrorAction SilentlyContinue
  if ($v -and $v.Value -ne $null -and "$($v.Value)" -ne '') {
    switch ($k) {
      'EV_ORIGIN_KIND'          { $prov['origin_kind'] = $v.Value }
      'EV_ORIGIN_PR'            { $prov['origin_pr'] = $v.Value }
      'EV_ORIGIN_COMMENT_ID'    { $prov['origin_comment_id'] = $v.Value }
      'EV_ORIGIN_COMMENT_URL'   { $prov['origin_comment_url'] = $v.Value }
      'EV_ORIGIN_AUTHOR'        { $prov['origin_author'] = $v.Value }
      'EV_SAMPLE_ID'            { $prov['sample_id'] = $v.Value }
      'EV_INCLUDE_INTEGRATION'  { $prov['include_integration'] = $v.Value }
      'EV_STRATEGY'             { $prov['strategy'] = $v.Value }
    }
  }
}

($prov | ConvertTo-Json -Depth 6) | Out-File -FilePath $outPath -Encoding utf8

if ($AppendStepSummary -and $env:GITHUB_STEP_SUMMARY) {
  $lines = @('### Run Provenance','')
  foreach ($k in $prov.Keys) { $lines += ('- {0}: {1}' -f $k,$prov[$k]) }
  $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

Write-Host ("Provenance written: {0}" -f $outPath)
