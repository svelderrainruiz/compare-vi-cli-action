<#
.SYNOPSIS
  Append a concise Compare VI block from compare-summary.json.
#>
[CmdletBinding()]
param(
  [string]$Path = 'compare-artifacts/compare-summary.json',
  [string]$Title = 'Compare VI'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

if (-not (Test-Path -LiteralPath $Path)) {
  ("### $Title`n- Summary: (missing) {0}" -f $Path) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  return
}
try { $j = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }

$lines = @("### $Title",'')
if ($j) {
  $lines += ('- Diff: {0}' -f $j.diff)
  $lines += ('- ExitCode: {0}' -f $j.exitCode)
  if ($j.compareDurationSeconds -ne $null) { $lines += ('- Duration (s): {0}' -f $j.compareDurationSeconds) }
  if ($j.mode) { $lines += ('- Mode: {0}' -f $j.mode) }
  $lines += ('- Summary: {0}' -f $Path)
} else {
  $lines += ('- Summary: failed to parse: {0}' -f $Path)
}

$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

