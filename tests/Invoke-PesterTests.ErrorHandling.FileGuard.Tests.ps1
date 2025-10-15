Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Dispatcher results path guard (file case)' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Resolve-Path (Join-Path $here '..')
    $script:repoRoot = $root
    $script:dispatcherPath = Join-Path $root 'Invoke-PesterTests.ps1'
    Test-Path -LiteralPath $script:dispatcherPath | Should -BeTrue
    Import-Module (Join-Path $root 'tests' '_helpers' 'DispatcherTestHelper.psm1') -Force
  }

  It 'fails and emits a guard crumb when ResultsPath points to a file' {
    $resultsFile = Join-Path $TestDrive 'blocked-results.txt'
    Set-Content -LiteralPath $resultsFile -Value 'blocked' -Encoding ascii

    $crumbPath = Join-Path $script:repoRoot 'tests/results/_diagnostics/guard.json'
    if (Test-Path -LiteralPath $crumbPath) { Remove-Item -LiteralPath $crumbPath -Force }

    $res = Invoke-DispatcherSafe -DispatcherPath $script:dispatcherPath -ResultsPath $resultsFile -IncludePatterns 'Invoke-PesterTests.ErrorHandling.*.ps1' -TimeoutSeconds 20
    $res.TimedOut | Should -BeFalse
    $res.ExitCode | Should -Not -Be 0

    $combined = ($res.StdOut + "`n" + $res.StdErr)
    $combined | Should -Match 'Results path points to a file'

    Test-Path -LiteralPath $crumbPath | Should -BeTrue
    $crumb = Get-Content -LiteralPath $crumbPath -Raw | ConvertFrom-Json
    $crumb.schema | Should -Be 'dispatcher-results-guard/v1'
    $crumb.path   | Should -Be $resultsFile
    $pattern = [regex]::Escape($resultsFile)
    $crumb.message | Should -Match $pattern
  }
}

