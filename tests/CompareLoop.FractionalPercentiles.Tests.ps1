Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..') | Select-Object -ExpandProperty Path
$helperPath = Join-Path $scriptRoot '_TestPathHelper.ps1'
if (Test-Path -LiteralPath $helperPath) { . $helperPath }
Import-Module (Join-Path $repoRoot 'module' 'CompareLoop' 'CompareLoop.psd1') -Force

Describe 'Invoke-IntegrationCompareLoop fractional percentile labels' -Tag 'Unit' {
  It 'emits underscored labels for fractional custom percentiles' {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("fracPct_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $base = Join-Path $tmp 'VI1.vi'; 'a' | Out-File -FilePath $base
    $head = Join-Path $tmp 'VI2.vi'; 'b' | Out-File -FilePath $head
  $exec = {
    param($cli,$b,$h,$argList)
    $delay = 5 + (Get-Random -Max 10)
    if (Get-Command Invoke-TestSleep -ErrorAction SilentlyContinue) {
      Invoke-TestSleep -Milliseconds $delay -FastMilliseconds 5
    } else {
      Start-Sleep -Milliseconds $delay
    }
    0
  }
    $fastMode = $false
    $fastEnv = $env:FAST_PESTER
    if (-not $fastEnv) { $fastEnv = $env:FAST_TESTS }
    if ($fastEnv -and $fastEnv.Trim() -match '^(?i:1|true|yes|on)$') { $fastMode = $true }
    $iterationCount = if ($fastMode) { 8 } else { 30 }
    $r = Invoke-IntegrationCompareLoop -Base $base -Head $head -MaxIterations $iterationCount -IntervalSeconds 0 -CompareExecutor $exec -BypassCliValidation -SkipValidation -PassThroughPaths -Quiet -CustomPercentiles '50,75,90,97.5,99.9'
    $r.Percentiles | Should -Not -BeNullOrEmpty
    $r.Percentiles.'p97_5' | Should -BeGreaterThan 0
    $r.Percentiles.'p99_9' | Should -BeGreaterThan 0
    # Ensure core baseline percentiles still resolve (p50/p90) and optionally p99 when computed
    $r.Percentiles.p50 | Should -BeGreaterThan 0
    $r.Percentiles.p90 | Should -BeGreaterThan 0
    if ($r.Percentiles.PSObject.Properties.Name -contains 'p99') {
      $r.Percentiles.p99 | Should -BeGreaterThan 0
    }
  }
}

