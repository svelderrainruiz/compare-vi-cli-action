#Requires -Version 7.0
# Tag: Integration (real loop mode with LVCompare)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
$script:BaseVi = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Base.vi')).Path
$script:HeadVi = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Head.vi')).Path
$script:Prereqs = $false
try {
  if ((Test-Path -LiteralPath $script:Canonical -PathType Leaf) -and (Test-Path -LiteralPath $script:BaseVi -PathType Leaf) -and (Test-Path -LiteralPath $script:HeadVi -PathType Leaf)) { $script:Prereqs = $true }
} catch { $script:Prereqs = $false }

BeforeAll {
  Import-Module (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) 'module' 'CompareLoop' 'CompareLoop.psd1') -Force
}

Describe 'Real LVCompare loop mode (single iteration)' -Tag Integration {
  It 'produces loop summary with percentiles (may be single sample)' -Skip:(-not $script:Prereqs) {
    $exec = {
      param($cli,$base,$head,$extraArgs)
      $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName=$cli; ArgumentList=@($base,$head) }
      $psi.RedirectStandardError=$true; $psi.RedirectStandardOutput=$true; $psi.UseShellExecute=$false
      $p = [System.Diagnostics.Process]::Start($psi)
      $p.WaitForExit()
      return $p.ExitCode
    }
    $res = Invoke-IntegrationCompareLoop -Base $script:BaseVi -Head $script:HeadVi -MaxIterations 1 -IntervalSeconds 0 -CompareExecutor $exec -QuantileStrategy Exact -Quiet -PassThroughPaths -BypassCliValidation -SkipValidation
    $res.Iterations | Should -Be 1
    $res.AverageSeconds | Should -BeGreaterThan 0
    $res.QuantileStrategy | Should -Be 'Exact'
    # Percentiles may exist with single sample (p50==p90==p99)
    if ($res.Percentiles) { $res.Percentiles.p50 | Should -BeGreaterThanOrEqual 0 }
  }
}
