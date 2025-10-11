($__testDir = $null)
try { if ($PSCommandPath) { $__testDir = Split-Path -Parent $PSCommandPath } } catch {}
if (-not $__testDir) { try { $__testDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {} }
if (-not $__testDir) { $__testDir = (Resolve-Path '.').Path }
. (Join-Path $__testDir '_TestPathHelper.ps1')

Describe 'Invoke-PesterTests summary emission' -Tag 'Unit' {
  It 'writes Selected Tests summary and rerun hint when integration disabled' {
    $repoRoot = Resolve-RepoRoot
    $dispatcher = Join-Path $repoRoot 'Invoke-PesterTests.ps1'
    Test-Path -LiteralPath $dispatcher | Should -BeTrue

    $workspace = Join-Path $TestDrive 'summary-run'
    $testsDir = Join-Path $workspace 'tests'
    $resultsDir = Join-Path $workspace 'results'
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    $testBody = @(
      "Describe 'SampleSuite' {",
      "  It 'passes quickly' { 1 | Should -Be 1 }",
      "}"
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $testsDir 'Sample.Tests.ps1') -Value $testBody -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $testsDir 'Another.Tests.ps1') -Value $testBody -Encoding UTF8

    $summaryPath = Join-Path $workspace 'gh-summary.md'
    $env:GITHUB_STEP_SUMMARY = $summaryPath
    $env:GITHUB_WORKFLOW = 'Validate'
    $env:GITHUB_REPOSITORY = 'labview/action'
    $env:GITHUB_REF_NAME = 'feature/test'
    $env:EV_SAMPLE_ID = 'sample-run-001'

    Push-Location $repoRoot
    try {
      & pwsh -NoLogo -NoProfile -File $dispatcher -TestsPath $testsDir -ResultsPath $resultsDir | Out-Null
    } finally {
      Pop-Location
      Remove-Item Env:\GITHUB_STEP_SUMMARY -ErrorAction SilentlyContinue
      Remove-Item Env:\GITHUB_WORKFLOW -ErrorAction SilentlyContinue
      Remove-Item Env:\GITHUB_REPOSITORY -ErrorAction SilentlyContinue
      Remove-Item Env:\GITHUB_REF_NAME -ErrorAction SilentlyContinue
      Remove-Item Env:\EV_SAMPLE_ID -ErrorAction SilentlyContinue
    }

    Test-Path -LiteralPath $summaryPath | Should -BeTrue
    $summaryText = Get-Content -LiteralPath $summaryPath -Raw
    $summaryText | Should -Match '### Selected Tests'
    $summaryText | Should -Match 'Sample.Tests.ps1'
    $summaryText | Should -Match 'Another.Tests.ps1'
    $summaryText | Should -Match 'IncludeIntegration: false'
    $summaryText | Should -Match 'Discovery: manual-scan'
    $summaryText | Should -Match '### Re-run \(gh\)'
    $summaryText | Should -Match 'include_integration=false'
    $summaryText | Should -Match 'sample_id=sample-run-001'
  }
}
