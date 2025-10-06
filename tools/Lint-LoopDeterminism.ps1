<#!
.SYNOPSIS
  Lint for CI loop determinism patterns in workflow/script content.
.DESCRIPTION
  Scans YAML/PS files for loop-related knobs and flags common non-deterministic patterns
  (high iteration counts, non-zero intervals, streaming quantiles, histograms).
  Defaults are notice-only; pass -FailOnViolation to exit non-zero when violations found.
.PARAMETER Paths
  File path(s) to scan (workflows, scripts, docs examples).
.PARAMETER MaxIterations
  Allowed cap for iterations (default 5).
.PARAMETER IntervalSeconds
  Allowed interval seconds (default 0).
.PARAMETER AllowedStrategies
  Allowed quantile strategies (default: Exact).
.PARAMETER FailOnViolation
  Exit with code 3 when violations found; otherwise exit 0 and print warnings.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromRemainingArguments=$true)]
  [string[]]$Paths,
  [object]$MaxIterations = 5,
  [object]$IntervalSeconds = 0,
  [string[]]$AllowedStrategies = @('Exact'),
  [switch]$FailOnViolation
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$violations = @()

# Tolerant coercion for MaxIterations/IntervalSeconds to avoid binding errors when callers pass strings or omit values.
$MaxI = 5
try {
  if ($MaxIterations -is [int]) { $MaxI = [int]$MaxIterations }
  else {
    [int]$tmp = 0
    if ([int]::TryParse("$MaxIterations", [ref]$tmp)) { $MaxI = $tmp }
  }
} catch { $MaxI = 5 }

$IntS = 0.0
try {
  if ($IntervalSeconds -is [double]) { $IntS = [double]$IntervalSeconds }
  else {
    [double]$dtmp = 0
    if ([double]::TryParse("$IntervalSeconds", [ref]$dtmp)) { $IntS = $dtmp }
  }
} catch { $IntS = 0.0 }
$patterns = @{
  IterYaml    = [regex]'(?im)\bloop-max-iterations\s*:\s*(?<n>\d+)' ;
  IterCli     = [regex]'(?im)-LoopIterations\s+(?<n>\d+)' ;
  IntYaml     = [regex]'(?im)\bloop-interval-seconds\s*:\s*(?<s>[0-9]+(?:\.[0-9]+)?)' ;
  IntCli      = [regex]'(?im)-LoopIntervalSeconds\s+(?<s>[0-9]+(?:\.[0-9]+)?)' ;
  StratYaml   = [regex]'(?im)\bquantile-strategy\s*:\s*(?<q>\w+)' ;
  StratCli    = [regex]'(?im)-QuantileStrategy\s+(?<q>\w+)' ;
  HistYaml    = [regex]'(?im)\bhistogram-bins\s*:\s*(?<h>\d+)' ;
  HistCli     = [regex]'(?im)-HistogramBins\s+(?<h>\d+)'
}

function Add-Violation([string]$file,[string]$kind,[string]$msg,[string]$line){
  $script:violations += [pscustomobject]@{ file=$file; kind=$kind; message=$msg; line=$line }
}

foreach ($p in $Paths) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "::notice::Skipping missing: $p"; continue }
  $text = Get-Content -LiteralPath $p -Raw
  # Iterations
  foreach ($m in $patterns.IterYaml.Matches($text)) {
    $n = [int]$m.Groups['n'].Value; if ($n -gt $MaxI) { Add-Violation $p 'Iterations' ("loop-max-iterations=$n > $MaxI") $m.Value }
  }
  foreach ($m in $patterns.IterCli.Matches($text)) {
    $n = [int]$m.Groups['n'].Value; if ($n -gt $MaxI) { Add-Violation $p 'Iterations' ("-LoopIterations $n > $MaxI") $m.Value }
  }
  # Interval
  foreach ($m in $patterns.IntYaml.Matches($text)) {
    $s = [double]$m.Groups['s'].Value; if ($s -ne $IntS) { Add-Violation $p 'Interval' ("loop-interval-seconds=$s != $IntS") $m.Value }
  }
  foreach ($m in $patterns.IntCli.Matches($text)) {
    $s = [double]$m.Groups['s'].Value; if ($s -ne $IntS) { Add-Violation $p 'Interval' ("-LoopIntervalSeconds $s != $IntS") $m.Value }
  }
  # Strategy
  foreach ($m in $patterns.StratYaml.Matches($text)) {
    $q = $m.Groups['q'].Value; if ($AllowedStrategies -notcontains $q) { Add-Violation $p 'Strategy' ("quantile-strategy=$q not in [$($AllowedStrategies -join ', ')]") $m.Value }
  }
  foreach ($m in $patterns.StratCli.Matches($text)) {
    $q = $m.Groups['q'].Value; if ($AllowedStrategies -notcontains $q) { Add-Violation $p 'Strategy' ("-QuantileStrategy $q not in [$($AllowedStrategies -join ', ')]") $m.Value }
  }
  # Histogram
  foreach ($m in $patterns.HistYaml.Matches($text)) {
    $h = [int]$m.Groups['h'].Value; if ($h -gt 0) { Add-Violation $p 'Histogram' ("histogram-bins=$h > 0 (disable for CI)") $m.Value }
  }
  foreach ($m in $patterns.HistCli.Matches($text)) {
    $h = [int]$m.Groups['h'].Value; if ($h -gt 0) { Add-Violation $p 'Histogram' ("-HistogramBins $h > 0 (disable for CI)") $m.Value }
  }
}

if ($violations.Count -gt 0) {
  Write-Host 'Loop determinism lint warnings:'
  foreach ($v in $violations) {
    Write-Host (" - [{0}] {1} :: {2}" -f $v.kind,$v.file,$v.message)
    if ($v.line) { Write-Host ("   > {0}" -f $v.line.Trim()) }
  }
  if ($FailOnViolation) { exit 3 } else { exit 0 }
} else {
  Write-Host 'Loop determinism lint: OK'
  exit 0
}
