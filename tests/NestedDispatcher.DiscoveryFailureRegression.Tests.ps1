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
    # Invoke dispatcher in an isolated PowerShell process so its Write-Error does not fail this parent test directly.
    $cmd = "pwsh -NoLogo -NoProfile -File `"$dispatcherCopy`" -TestsPath tests -ResultsPath results -IncludeIntegration false"
    $output = & pwsh -NoLogo -NoProfile -Command $cmd 2>&1
    $exit = $LASTEXITCODE
      $summaryJson = Join-Path $workspace 'results' 'pester-summary.json'
      Test-Path $summaryJson | Should -BeTrue
      $json = Get-Content $summaryJson -Raw | ConvertFrom-Json
      $discoveryFailed = ($output -match 'Discovery in .* failed with:')
      # Dispatcher should mark exit non-zero OR classify via discoveryFailures; assert both signals align.
      $exit | Should -Not -Be 0
      ($json.discoveryFailures -as [int]) | Should -BeGreaterThan 0
      # Text pattern is a secondary confirmation (do not fail test if JSON already shows discovery failures)
      if (-not $discoveryFailed) {
        Write-Host '[nested-discovery] Console pattern not matched; relying on JSON discoveryFailures=' $json.discoveryFailures -ForegroundColor Yellow
      }
    } finally {
      Pop-Location
    }
  }
}
