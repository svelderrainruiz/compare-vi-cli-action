# Regression: Discovery failure inside nested dispatcher should be surfaced (non-zero exit or explicit error lines)
Describe 'Nested Dispatcher Discovery Failure Regression' -Tag 'Unit' {
  It 'flags discovery failure instead of treating run as success' {
    $workspace = Join-Path $TestDrive 'nested-failure'
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    $testsDir = Join-Path $workspace 'tests'
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

    # Create a syntactically invalid test file (missing closing braces) to force discovery failure
    $badLines = @(
      'Describe "Broken Block" {'
      '  It "will not parse" {'
      '    # Missing closing brace below triggers parser error'
      '    1 | Should -Be 1'
    )
    Set-Content -Path (Join-Path $testsDir 'Broken.Tests.ps1') -Value $badLines -Encoding UTF8

    $dispatcherCopy = Join-Path $workspace 'Invoke-PesterTests.ps1'
    Copy-Item -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-PesterTests.ps1') -Destination $dispatcherCopy

    Push-Location $workspace
    try {
      $output = & $dispatcherCopy -TestsPath 'tests' -IncludeIntegration 'false' -ResultsPath 'results' 2>&1
      $exit = $LASTEXITCODE
      $discoveryFailed = ($output -match 'Discovery in .* failed with:')
      # Dispatcher should now mark exit non-zero and include discoveryFailures in JSON summary.
      $exit | Should -Not -Be 0
      $discoveryFailed | Should -BeTrue
      $summaryJson = Join-Path $workspace 'results' 'pester-summary.json'
      Test-Path $summaryJson | Should -BeTrue
      $json = Get-Content $summaryJson -Raw | ConvertFrom-Json
      ($json.discoveryFailures -as [int]) | Should -BeGreaterThan 0
    } finally {
      Pop-Location
    }
  }
}
