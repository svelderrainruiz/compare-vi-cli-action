Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Invoke-PesterTests.ps1 Dispatcher' -Tag 'Unit' {
  BeforeAll {
    $repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $scriptPath = Join-Path $repoRoot 'Invoke-PesterTests.ps1'
  }

  It 'writes a guard crumb when ResultsPath points to a file' {
    $resultsFile = Join-Path $TestDrive 'guard-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null

    $crumbPath = Join-Path $repoRoot 'tests/results/_diagnostics/guard.json'
    if (Test-Path -LiteralPath $crumbPath) { Remove-Item -LiteralPath $crumbPath -Force }

    Push-Location $repoRoot
    try {
      $output = & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IntegrationMode exclude -TestsPath 'tests' 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    $exitCode | Should -Be 1
    $output   | Should -Not -BeNullOrEmpty

    $joinedOutput = $output | Out-String
    $joinedOutput | Should -Match 'guard crumb'
    $joinedOutput | Should -Match ([regex]::Escape('tests/results/_diagnostics/guard.json'))

    Test-Path -LiteralPath $crumbPath | Should -BeTrue
    $crumb = Get-Content -LiteralPath $crumbPath -Raw | ConvertFrom-Json -Depth 4
    $crumb.schema | Should -Be 'dispatcher-results-guard/v1'
    $crumb.path   | Should -Be $resultsFile
  }

  It 'resolves IntegrationMode include to enable integration tests' {
    $resultsFile = Join-Path $TestDrive 'mode-include-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null

    Push-Location $repoRoot
    try {
      $output = & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IntegrationMode include -TestsPath 'tests' 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    $exitCode | Should -Be 1
    $joined = $output | Out-String
    $joined | Should -Match 'Integration Mode: include'
    $joined | Should -Match 'Include Integration: True'
  }

  It 'honors INCLUDE_INTEGRATION for auto integration mode' {
    $resultsFile = Join-Path $TestDrive 'mode-auto-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null
    $previousValue = $env:INCLUDE_INTEGRATION
    $env:INCLUDE_INTEGRATION = 'true'

    Push-Location $repoRoot
    try {
      $output = & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IntegrationMode auto -TestsPath 'tests' 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
      if ($null -ne $previousValue) {
        $env:INCLUDE_INTEGRATION = $previousValue
      } else {
        Remove-Item Env:\INCLUDE_INTEGRATION -ErrorAction SilentlyContinue
      }
    }

    $exitCode | Should -Be 1
    $joined = $output | Out-String
    $joined | Should -Match 'Integration Mode: auto'
    $joined | Should -Match 'Include Integration: True'
    $joined | Should -Match 'Mode Source: auto:env:INCLUDE_INTEGRATION'
  }

  It 'maintains legacy IncludeIntegration compatibility' {
    $resultsFile = Join-Path $TestDrive 'legacy-include-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null

    Push-Location $repoRoot
    try {
      $output = & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IncludeIntegration true -TestsPath 'tests' 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    $exitCode | Should -Be 1
    $joined = $output | Out-String
    $joined | Should -Match 'Integration Mode: include'
    $joined | Should -Match 'Include Integration: True'
    $joined | Should -Match 'IncludeIntegration is deprecated'
  }

  It 'does not override an existing FAST_PESTER value when integrations excluded' {
    $resultsFile = Join-Path $TestDrive 'fast-preserve-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null

    $hadFast = Test-Path Env:\FAST_PESTER
    $previousFast = $null
    if ($hadFast) { $previousFast = $env:FAST_PESTER }

    try {
      $env:FAST_PESTER = '0'
      Push-Location $repoRoot
      try {
        & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IntegrationMode exclude -TestsPath 'tests' | Out-Null
      } finally {
        Pop-Location
      }

      Test-Path Env:\FAST_PESTER | Should -BeTrue
      $env:FAST_PESTER | Should -Be '0'
    } finally {
      if ($hadFast) {
        $env:FAST_PESTER = $previousFast
      } else {
        Remove-Item Env:\FAST_PESTER -ErrorAction SilentlyContinue
      }
    }
  }

  It 'honors FAST_TESTS when determining auto fast mode' {
    $resultsFile = Join-Path $TestDrive 'fast-tests-blocker.txt'
    New-Item -ItemType File -Path $resultsFile -Force | Out-Null

    $hadFast = Test-Path Env:\FAST_PESTER
    $previousFast = if ($hadFast) { $env:FAST_PESTER } else { $null }
    $hadFastTests = Test-Path Env:\FAST_TESTS
    $previousFastTests = if ($hadFastTests) { $env:FAST_TESTS } else { $null }

    try {
      Remove-Item Env:\FAST_PESTER -ErrorAction SilentlyContinue
      $env:FAST_TESTS = '0'

      Push-Location $repoRoot
      try {
        & pwsh -NoLogo -NoProfile -File $scriptPath -ResultsPath $resultsFile -IntegrationMode exclude -TestsPath 'tests' | Out-Null
      } finally {
        Pop-Location
      }

      Test-Path Env:\FAST_PESTER | Should -BeFalse
      $env:FAST_TESTS | Should -Be '0'
    } finally {
      if ($hadFast) {
        $env:FAST_PESTER = $previousFast
      } else {
        Remove-Item Env:\FAST_PESTER -ErrorAction SilentlyContinue
      }
      if ($hadFastTests) {
        $env:FAST_TESTS = $previousFastTests
      } else {
        Remove-Item Env:\FAST_TESTS -ErrorAction SilentlyContinue
      }
    }
  }

  It 'emits placeholder artifacts with null timing metrics when no tests are discovered' {
    $workspace = Join-Path $TestDrive 'zero-tests'
    $testsDir = Join-Path $workspace 'tests'
    $resultsDir = Join-Path $workspace 'results'
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

    Push-Location $repoRoot
    try {
      & pwsh -NoLogo -NoProfile -File $scriptPath -TestsPath $testsDir -ResultsPath $resultsDir -IntegrationMode exclude | Out-Null
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    $exitCode | Should -Be 0

    $summaryPath = Join-Path $resultsDir 'pester-summary.json'
    Test-Path -LiteralPath $summaryPath | Should -BeTrue
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 4
    $summary.total | Should -Be 0
    $summary.meanTest_ms | Should -Be $null
    $summary.p95Test_ms | Should -Be $null
    $summary.maxTest_ms | Should -Be $null
    $summary.timedOut | Should -BeFalse

    $xmlPath = Join-Path $resultsDir 'pester-results.xml'
    Test-Path -LiteralPath $xmlPath | Should -BeTrue

    $sessionIndexPath = Join-Path $resultsDir 'session-index.json'
    Test-Path -LiteralPath $sessionIndexPath | Should -BeTrue
    $session = Get-Content -LiteralPath $sessionIndexPath -Raw | ConvertFrom-Json -Depth 4
    $session.summary.meanTest_ms | Should -Be $null
    $session.summary.maxTest_ms | Should -Be $null
  }

  AfterEach {
    $crumbPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'tests/results/_diagnostics/guard.json'
    if (Test-Path -LiteralPath $crumbPath) {
      Remove-Item -LiteralPath $crumbPath -Force
      $diagDir = Split-Path -Parent $crumbPath
      if ((Test-Path -LiteralPath $diagDir) -and -not (Get-ChildItem -LiteralPath $diagDir -Force)) {
        Remove-Item -LiteralPath $diagDir -Force
      }
    }
  }
}
