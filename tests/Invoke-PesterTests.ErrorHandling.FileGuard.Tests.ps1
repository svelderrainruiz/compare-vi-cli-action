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

  It 'clears a stale guard crumb before launching the dispatcher' {
    $crumbPath = Join-Path $script:repoRoot 'tests/results/_diagnostics/guard.json'
    $crumbDir = Split-Path -Parent $crumbPath
    if (-not (Test-Path -LiteralPath $crumbDir -PathType Container)) {
      New-Item -ItemType Directory -Path $crumbDir -Force | Out-Null
    }

    $previousCrumb = $null
    $hadCrumb = $false
    if (Test-Path -LiteralPath $crumbPath -PathType Leaf) {
      $previousCrumb = Get-Content -LiteralPath $crumbPath -Raw
      $hadCrumb = $true
    }

    try {
      # Seed a stale crumb to simulate a prior guarded failure.
      $stale = '{"schema":"dispatcher-results-guard/v1","message":"stale"}'
      Set-Content -LiteralPath $crumbPath -Value $stale -Encoding utf8

      $resultsDir = Join-Path $TestDrive 'clean-results'
      $stdout = & pwsh -NoLogo -NoProfile -File $script:dispatcherPath -ResultsPath $resultsDir -GuardResetOnly 2>&1
      $exitCode = $LASTEXITCODE

      $exitCode | Should -Be 0
      ($stdout -join [Environment]::NewLine) | Should -Match '\[guard\] Cleared stale dispatcher guard crumb'

      Test-Path -LiteralPath $crumbPath | Should -BeFalse
    } finally {
      if ($hadCrumb) {
        if (-not (Test-Path -LiteralPath $crumbDir -PathType Container)) {
          New-Item -ItemType Directory -Path $crumbDir -Force | Out-Null
        }
        Set-Content -LiteralPath $crumbPath -Value $previousCrumb -Encoding utf8
      } elseif (Test-Path -LiteralPath $crumbPath) {
        Remove-Item -LiteralPath $crumbPath -Force
      }
    }
  }
}

