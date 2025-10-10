<#
.SYNOPSIS
  Aggregate per-category Pester session-index totals and append a compact block to job summary.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$BaseDir,
  [Parameter(Mandatory=$true)][string[]]$Categories
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

$rows = @()
foreach ($c in $Categories) {
  $idx = Join-Path (Join-Path $BaseDir $c) 'tests/results/session-index.json'
  if (-not (Test-Path -LiteralPath $idx)) {
    # Try direct path if artifact unpacked without nested structure
    $alt = Join-Path (Join-Path $BaseDir $c) 'session-index.json'
    if (Test-Path -LiteralPath $alt) { $idx = $alt } else { $idx = $null }
  }
  if ($idx) {
    try { $j = Get-Content -LiteralPath $idx -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }
  } else { $j = $null }
  $rows += [pscustomobject]@{
    category = $c
    status   = if ($j) { $j.status } else { 'n/a' }
    total    = if ($j) { $j.total } else { $null }
    passed   = if ($j) { $j.passed } else { $null }
    failed   = if ($j) { $j.failed } else { $null }
    errors   = if ($j) { $j.errors } else { $null }
    skipped  = if ($j) { $j.skipped } else { $null }
    duration = if ($j) { $j.duration_s } else { $null }
  }
}

# Aggregate overview
$valid = $rows | Where-Object { $_.total -ne $null }
$sum = @{
  total   = ($valid | Measure-Object -Property total   -Sum).Sum
  passed  = ($valid | Measure-Object -Property passed  -Sum).Sum
  failed  = ($valid | Measure-Object -Property failed  -Sum).Sum
  errors  = ($valid | Measure-Object -Property errors  -Sum).Sum
  skipped = ($valid | Measure-Object -Property skipped -Sum).Sum
  duration= ($valid | Measure-Object -Property duration -Sum).Sum
}
$overall = if (([int]$sum.failed + [int]$sum.errors) -gt 0) { 'failure' } else { 'success' }

# Optional: resolve artifact download URLs for each category
function Try-GetCommand {
  param([string]$Name)
  try { return (Get-Command -Name $Name -ErrorAction Stop) } catch { return $null }
}
$artifactLinks = @{}
$gh = Try-GetCommand gh
if ($gh -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) {
  try {
    $resp = & $gh.Source api "repos/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)/artifacts?per_page=100" 2>$null
    if ($LASTEXITCODE -eq 0 -and $resp) {
      $j = $resp | ConvertFrom-Json
      foreach ($a in @($j.artifacts)) {
        if ($a.name -and $a.archive_download_url) {
          $artifactLinks[$a.name] = $a.archive_download_url
        }
      }
    }
  } catch {}
}

$lines = @()
$lines += '### Pester Overview'
$lines += ''
$lines += ('- Result: {0}' -f $overall)
$lines += ('- Totals: tests={0} passed={1} failed={2} errors={3} skipped={4}' -f $sum.total,$sum.passed,$sum.failed,$sum.errors,$sum.skipped)
if ($sum.duration -ne $null) { $lines += ('- Duration (s): {0}' -f [math]::Round($sum.duration,3)) }
$lines += ''
$lines += '### Pester Categories'
$lines += ''
foreach ($r in $rows) {
  $name = "orchestrated-pester-results-$($r.category)"
  $link = if ($artifactLinks.ContainsKey($name)) { $artifactLinks[$name] } else { $null }
  $line = ('- {0}: status={1}, total={2}, failed={3}, errors={4}, duration={5}' -f $r.category,$r.status,$r.total,$r.failed,$r.errors,$r.duration)
  if ($link) { $line += " — [artifact]($link)" }
  $lines += $line
}
$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

