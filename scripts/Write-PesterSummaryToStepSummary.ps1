<#
.SYNOPSIS
  Writes a condensed Pester test summary to the GitHub Actions step summary (GITHUB_STEP_SUMMARY).

.DESCRIPTION
  Consumes the dispatcher-generated summary sources (prefers JSON -> TXT fallback) inside tests/results.
  Produces a markdown section with totals, pass/fail counts, duration, and (if present) a table of failed tests.

.USAGE
  pwsh -File scripts/Write-PesterSummaryToStepSummary.ps1 -Verbose
  # In a workflow step AFTER tests run:
  # - name: Publish Pester Summary
  #   shell: pwsh
  #   run: pwsh -File scripts/Write-PesterSummaryToStepSummary.ps1

.NOTES
  Requires environment variable GITHUB_STEP_SUMMARY; if absent, script no-ops with a warning.
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'tests/results',
  [ValidateSet('None','Details','DetailsOpen')][string]$FailedTestsCollapseStyle = 'Details',
  [switch]$IncludeFailedDurations = $true,
  [ValidateSet('None','Relative')][string]$FailedTestsLinkStyle = 'None',
  [switch]$EmitFailureBadge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:GITHUB_STEP_SUMMARY) {
  Write-Warning 'GITHUB_STEP_SUMMARY not set; skipping summary emission.'
  return
}

$summaryPath = Join-Path $ResultsDir 'pester-summary.json'
$txtPath = Join-Path $ResultsDir 'pester-summary.txt'
$xmlPath = Join-Path $ResultsDir 'pester-results.xml'

function Write-Line($s) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $s -Encoding UTF8 }

Write-Verbose "Using summary target: $env:GITHUB_STEP_SUMMARY"

$summary = $null
if (Test-Path $summaryPath) {
  try { $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json } catch { Write-Warning ("Failed to parse {0}: {1}" -f $summaryPath, $_.Exception.Message) }
}

$totals = $null
if ($summary) {
  $totals = $summary | Select-Object -First 1
}
elseif (Test-Path $txtPath) {
  # Fallback: parse minimal metrics from text summary lines
  $lines = Get-Content $txtPath -ErrorAction SilentlyContinue
  $hash = @{}
  foreach ($l in $lines) { if ($l -match '^(Total Tests|Passed|Failed|Errors|Skipped):\s+(\d+)') { $hash[$matches[1]] = [int]$matches[2] } }
  if ($hash.Count) { $totals = [pscustomobject]@{ Total=$hash['Total Tests']; Passed=$hash['Passed']; Failed=$hash['Failed']; Errors=$hash['Errors']; Skipped=$hash['Skipped'] } }
}

Write-Line '## Pester Test Summary'

# Optional badge line for quick copy into PR comments
if ($EmitFailureBadge) {
  $badge = if (($totals.Failed ?? $totals.failed) -gt 0) {
    "**❌ Tests Failed:** $($totals.Failed ?? $totals.failed) of $($totals.Total ?? $totals.total)"
  } else {
    "**✅ All Tests Passed:** $($totals.Total ?? $totals.total)"
  }
  Write-Line ''
  Write-Line $badge
}

if (-not $totals) {
  Write-Line '> No Pester summary data found.'
  return
}

Write-Line ''
Write-Line '| Metric | Value |'
Write-Line '|--------|-------|'
Write-Line ("| Total | {0} |" -f ($totals.Total ?? $totals.total ?? $totals.Tests))
Write-Line ("| Passed | {0} |" -f ($totals.Passed ?? $totals.passed))
Write-Line ("| Failed | {0} |" -f ($totals.Failed ?? $totals.failed))
if ($totals.Errors -ne $null -or $totals.errors -ne $null) { Write-Line ("| Errors | {0} |" -f ($totals.Errors ?? $totals.errors)) }
if ($totals.Skipped -ne $null -or $totals.skipped -ne $null) { Write-Line ("| Skipped | {0} |" -f ($totals.Skipped ?? $totals.skipped)) }
if ($totals.Duration -ne $null -or $totals.duration -ne $null) { Write-Line ("| Duration (s) | {0} |" -f ($totals.Duration ?? $totals.duration)) }

# Optional failed test details from failures JSON if present
$failJson = Join-Path $ResultsDir 'pester-failures.json'
if (Test-Path $failJson) {
  try {
    $failData = Get-Content $failJson -Raw | ConvertFrom-Json
    $failed = @($failData.results | Where-Object { $_.result -eq 'Failed' })
    if ($failed.Count) {
      Write-Line ''
      switch ($FailedTestsCollapseStyle) {
        'None' {
          Write-Line '### Failed Tests'
          Write-Line ''
        }
        'Details' {
          Write-Line '<details><summary><strong>Failed Tests</strong></summary>'
          Write-Line ''
        }
        'DetailsOpen' {
          Write-Line '<details open><summary><strong>Failed Tests</strong></summary>'
          Write-Line ''
        }
      }
      if ($IncludeFailedDurations) {
        Write-Line '| Name | Duration (s) |'
        Write-Line '|------|--------------|'
      } else {
        Write-Line '| Name |'
        Write-Line '|------|'
      }
      foreach ($f in $failed) {
        $name = $f.Name
        if ($FailedTestsLinkStyle -eq 'Relative') {
          $candidate = ($name -replace '::','.') -replace '\s+','.'
            $leaf = ($candidate -split '[\s]')[0]
            $fileRel = "tests/$leaf.Tests.ps1"
            $name = "[$($f.Name)]($fileRel)"
        }
        if ($IncludeFailedDurations) {
          Write-Line ("| {0} | {1} |" -f ($name -replace '\|','/'), ($f.Duration ?? $f.duration))
        } else {
          Write-Line ("| {0} |" -f ($name -replace '\|','/'))
        }
      }
      if ($FailedTestsCollapseStyle -like 'Details*') { Write-Line '</details>' }
    }
  } catch { Write-Warning ("Failed to parse failure JSON: {0}" -f $_.Exception.Message) }
}

Write-Host 'Pester summary written to GitHub step summary.' -ForegroundColor Green