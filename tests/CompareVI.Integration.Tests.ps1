#Requires -Version 7.0
# Tag: Integration (executes the real CLI on self-hosted)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  $here = Split-Path -Parent $PSCommandPath
  $repoRoot = Resolve-Path (Join-Path $here '..')
  . (Join-Path $repoRoot 'scripts' 'CompareVI.ps1')

  $Canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
  $BaseVi = $env:LV_BASE_VI
  $HeadVi = $env:LV_HEAD_VI
  $script:Canonical = $Canonical
  $script:BaseVi = $BaseVi
  $script:HeadVi = $HeadVi
}

Describe 'Invoke-CompareVI (real CLI on self-hosted)' -Tag Integration {
  It 'has required files present' {
    if (-not (Test-Path -LiteralPath $Canonical -PathType Leaf)) {
      Write-Host "ERROR: LVCompare.exe not found at canonical path: $Canonical"
      Write-Host "Install LabVIEW 2025 Q3 or later with LabVIEW Compare CLI"
      Write-Host "See docs/SELFHOSTED_CI_SETUP.md for setup instructions"
    }
    Test-Path -LiteralPath $Canonical -PathType Leaf | Should -BeTrue

    if (-not $BaseVi) {
      Write-Host "ERROR: LV_BASE_VI environment variable not set"
      Write-Host "Set repository variable LV_BASE_VI to path of a test VI file"
      Write-Host "See docs/SELFHOSTED_CI_SETUP.md for setup instructions"
    }
    if (-not $HeadVi) {
      Write-Host "ERROR: LV_HEAD_VI environment variable not set"
      Write-Host "Set repository variable LV_HEAD_VI to path of a test VI file (different from LV_BASE_VI)"
      Write-Host "See docs/SELFHOSTED_CI_SETUP.md for setup instructions"
    }
    Test-Path -LiteralPath $BaseVi -PathType Leaf | Should -BeTrue
    Test-Path -LiteralPath $HeadVi -PathType Leaf | Should -BeTrue
  }

  It 'exit 0 => diff=false when base=head' {
    $res = Invoke-CompareVI -Base $BaseVi -Head $BaseVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 0
    $res.Diff | Should -BeFalse
    $res.CliPath | Should -Be (Resolve-Path $Canonical).Path
  }

  It 'exit 1 => diff=true when base!=head' {
    $res = Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue
  }

  It 'fail-on-diff=true throws after outputs are written for diff' {
    $tmpOut = Join-Path $env:TEMP ("comparevi-outputs-{0}.txt" -f ([guid]::NewGuid()))
    { Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -GitHubOutputPath $tmpOut -FailOnDiff:$true } | Should -Throw
    (Get-Content -LiteralPath $tmpOut -Raw) | Should -Match '(^|\n)diff=true($|\n)'
    Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'generates HTML report from real comparison results' {
    # Run comparison (with diff expected)
    $res = Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue

    # Generate HTML report
    $resultsDir = Join-Path $here 'results'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    $htmlPath = Join-Path $resultsDir 'integration-compare-report.html'
    
    $renderer = Join-Path (Split-Path -Parent $here) 'scripts' 'Render-CompareReport.ps1'
    & $renderer `
      -Command $res.Command `
      -ExitCode $res.ExitCode `
      -Diff ($res.Diff.ToString().ToLower()) `
      -CliPath $res.CliPath `
      -OutputPath $htmlPath

    # Verify HTML was created
    Test-Path -LiteralPath $htmlPath | Should -BeTrue
    
    # Verify HTML contains expected content
    $html = Get-Content -LiteralPath $htmlPath -Raw
    $html | Should -Match 'Compare VI Report'
    $html | Should -Match 'Differences detected'
    $html | Should -Match 'Exit code.*1'
  }
}
