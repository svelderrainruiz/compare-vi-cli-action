<#
.SYNOPSIS
  Append a concise Fixture Drift block from drift-summary.json (best-effort).
#>
[CmdletBinding()]
param(
  [string]$Dir = 'results/fixture-drift',
  [string]$SummaryFile = 'drift-summary.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

$path = if ($Dir) { Join-Path $Dir $SummaryFile } else { $SummaryFile }
if (-not (Test-Path -LiteralPath $path)) {
  ("### Fixture Drift`n- Summary: (missing) {0}" -f $path) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  return
}
try {
  $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
  ("### Fixture Drift`n- Summary: failed to parse: {0}" -f $path) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  return
}

$lines = @('### Fixture Drift','')
$lines += ('- Summary: {0}' -f $path)
function AddCounts($obj){
  if (-not $obj) { return }
  foreach ($k in ($obj.PSObject.Properties.Name | Sort-Object)) {
    $v = $obj.$k
    $lines += ('- {0}: {1}' -f $k,$v)
  }
}
if ($json.summaryCounts) { AddCounts $json.summaryCounts }
elseif ($json.counts) { AddCounts $json.counts }

if ($json.notes) {
  $n = $json.notes
  if ($n -is [array]) { foreach ($x in $n) { $lines += ('- Note: {0}' -f $x) } }
  else { $lines += ('- Note: {0}' -f $n) }
}

$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

