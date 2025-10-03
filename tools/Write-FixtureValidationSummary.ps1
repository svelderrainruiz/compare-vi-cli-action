param(
  [string]$ValidationJson = 'fixture-validation.json',
  [string]$DeltaJson = 'fixture-validation-delta.json',
  [string]$SummaryPath = $env:GITHUB_STEP_SUMMARY
)
$ErrorActionPreference = 'Stop'

function Get-JsonContent($p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

$validation = Get-JsonContent $ValidationJson
$delta = Get-JsonContent $DeltaJson

if (-not $SummaryPath) { Write-Host 'No GITHUB_STEP_SUMMARY set; printing summary instead.' }

$lines = @('# Fixture Validation Summary')
if ($validation) {
  $lines += ''
  $lines += '## Current Snapshot'
  if ($validation.ok) { $lines += 'Status: OK' } else { $lines += 'Status: Issues Detected' }
  if ($validation.summaryCounts) {
    $sc = $validation.summaryCounts
    $lines += ('Counts: missing={0} untracked={1} tooSmall={2} hashMismatch={3} manifestError={4} duplicate={5} schema={6}' -f `
      $sc.missing,$sc.untracked,$sc.tooSmall,$sc.hashMismatch,$sc.manifestError,$sc.duplicate,$sc.schema)
  }
}
if ($delta) {
  $lines += ''
  $lines += '## Delta'
  if ($delta.deltaCounts) {
    $pairs = @()
    foreach ($kv in $delta.deltaCounts.GetEnumerator()) { $pairs += ("{0}={1}" -f $kv.Key,$kv.Value) }
    $lines += ('Changed Categories: ' + ($pairs -join ', '))
  } else {
    $lines += 'Changed Categories: (none)'
  }
  $lines += ('New Structural Issues: ' + $delta.newStructuralIssues.Count)
  $lines += ('Will Fail: ' + $delta.willFail)
}

$body = ($lines -join [Environment]::NewLine)
if ($SummaryPath) { Add-Content -LiteralPath $SummaryPath -Value $body -Encoding utf8 } else { Write-Host $body }
