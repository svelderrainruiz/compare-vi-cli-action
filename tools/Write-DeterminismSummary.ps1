<#
.SYNOPSIS
  Append a concise Determinism block to the job summary based on LOOP_* envs.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:GITHUB_STEP_SUMMARY) { return }

function Get-EnvOr($name,[string]$fallback) {
  if ($env:$name -ne $null -and "$($env:$name)" -ne '') { return "$($env:$name)" } else { return $fallback }
}

$lines = @('### Determinism','')
$lines += ('- Profile: {0}' -f (if ($env:LVCI_DETERMINISTIC) { 'deterministic' } else { 'default' }))
$lines += ('- Iterations: {0}' -f (Get-EnvOr 'LOOP_MAX_ITERATIONS' 'n/a'))
$lines += ('- IntervalSeconds: {0}' -f (Get-EnvOr 'LOOP_INTERVAL_SECONDS' '0'))
$lines += ('- QuantileStrategy: {0}' -f (Get-EnvOr 'LOOP_QUANTILE_STRATEGY' 'Exact'))
$lines += ('- HistogramBins: {0}' -f (Get-EnvOr 'LOOP_HISTOGRAM_BINS' '0'))
$lines += ('- ReconcileEvery: {0}' -f (Get-EnvOr 'LOOP_RECONCILE_EVERY' '0'))
$lines += ('- AdaptiveInterval: {0}' -f (Get-EnvOr 'LOOP_ADAPTIVE' '0'))

$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

