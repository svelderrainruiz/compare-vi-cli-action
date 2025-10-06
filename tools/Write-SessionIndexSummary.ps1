<#
.SYNOPSIS
  Append a concise Session block from tests/results/session-index.json.
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'tests/results',
  [string]$FileName = 'session-index.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

$path = if ($ResultsDir) { Join-Path $ResultsDir $FileName } else { $FileName }
if (-not (Test-Path -LiteralPath $path)) {
  ("### Session`n- File: (missing) {0}" -f $path) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  return
}
try { $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $j = $null }

$lines = @('### Session','')
if ($j) {
  if ($j.status) { $lines += ('- Status: {0}' -f $j.status) }
  if ($j.total -ne $null) { $lines += ('- Total: {0}' -f $j.total) }
  if ($j.passed -ne $null) { $lines += ('- Passed: {0}' -f $j.passed) }
  if ($j.failed -ne $null) { $lines += ('- Failed: {0}' -f $j.failed) }
  if ($j.errors -ne $null) { $lines += ('- Errors: {0}' -f $j.errors) }
  if ($j.skipped -ne $null) { $lines += ('- Skipped: {0}' -f $j.skipped) }
  if ($j.duration_s -ne $null) { $lines += ('- Duration (s): {0}' -f $j.duration_s) }
  $lines += ('- File: {0}' -f $path)
} else {
  $lines += ('- File: failed to parse: {0}' -f $path)
}

$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

