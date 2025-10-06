<#
.SYNOPSIS
  Append a concise Determinism block to the job summary based on LOOP_* envs.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
  if (-not $env:GITHUB_STEP_SUMMARY) { exit 0 }

  function Get-EnvOr($name,[string]$fallback) {
    try {
      $val = [System.Environment]::GetEnvironmentVariable($name)
    } catch { $val = $null }
    if ($null -ne $val -and "$val" -ne '') { return "$val" } else { return $fallback }
  }

  $lines = @('### Determinism','')
  $profile = if ($env:LVCI_DETERMINISTIC) { 'deterministic' } else { 'default' }
  $lines += ('- Profile: {0}' -f $profile)
  $lines += ('- Iterations: {0}' -f (Get-EnvOr 'LOOP_MAX_ITERATIONS' 'n/a'))
  $lines += ('- IntervalSeconds: {0}' -f (Get-EnvOr 'LOOP_INTERVAL_SECONDS' '0'))
  $lines += ('- QuantileStrategy: {0}' -f (Get-EnvOr 'LOOP_QUANTILE_STRATEGY' 'Exact'))
  $lines += ('- HistogramBins: {0}' -f (Get-EnvOr 'LOOP_HISTOGRAM_BINS' '0'))
  $lines += ('- ReconcileEvery: {0}' -f (Get-EnvOr 'LOOP_RECONCILE_EVERY' '0'))
  $lines += ('- AdaptiveInterval: {0}' -f (Get-EnvOr 'LOOP_ADAPTIVE' '0'))

  $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8 -ErrorAction SilentlyContinue
  exit 0
} catch {
  Write-Host "::notice::Write-DeterminismSummary failed: $_"
  exit 0
}
