#Requires -Version 7.0
# Tag: Integration (single real CLI invocation using repo VIs)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
$script:BaseVi = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Base.vi')).Path
$script:HeadVi = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Head.vi')).Path

$script:Prereqs = $false
try {
  if ((Test-Path -LiteralPath $script:Canonical -PathType Leaf) -and (Test-Path -LiteralPath $script:BaseVi -PathType Leaf) -and (Test-Path -LiteralPath $script:HeadVi -PathType Leaf)) {
    $script:Prereqs = $true
  }
} catch { $script:Prereqs = $false }

BeforeAll {
  . (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')) 'scripts' 'CompareVI.ps1')
  $script:ResultsDir = Join-Path $PSScriptRoot 'results-single'
  New-Item -ItemType Directory -Path $script:ResultsDir -Force | Out-Null
}

Describe 'Single real LVCompare invocation (repo Base.vi vs Head.vi)' -Tag Integration {
  It 'produces expected diff outputs and HTML report' -Skip:(-not $script:Prereqs) {
    $res = Invoke-CompareVI -Base $script:BaseVi -Head $script:HeadVi -LvComparePath $script:Canonical -FailOnDiff:$false
    $res.ExitCode | Should -BeIn @(0,1)
    $res.Command | Should -Match 'LVCompare.exe'

    # Render HTML report for PR body usage
    $htmlPath = Join-Path $script:ResultsDir 'pr-body-compare-report.html'
    $renderer = Join-Path (Split-Path (Resolve-Path (Join-Path $PSScriptRoot '..'))) 'scripts' 'Render-CompareReport.ps1'
    & $renderer -Command $res.Command -ExitCode $res.ExitCode -Diff ($res.Diff.ToString().ToLower()) -CliPath $res.CliPath -OutputPath $htmlPath -DurationSeconds $res.CompareDurationSeconds
    Test-Path -LiteralPath $htmlPath | Should -BeTrue
    $html = Get-Content -LiteralPath $htmlPath -Raw
    $html | Should -Match 'Compare VI Report'
  }
}
