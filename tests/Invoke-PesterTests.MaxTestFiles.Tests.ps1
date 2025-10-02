Describe 'Invoke-PesterTests MaxTestFiles selection' -Tag 'Unit' {
  $dispatcher = Join-Path $PSScriptRoot '..' 'Invoke-PesterTests.ps1'

  It 'runs only the first test file when MaxTestFiles=1' {
    # Use existing tests directory; choose MaxTestFiles=1
    $resultsDir = Join-Path $PSScriptRoot 'results-maxtestfiles'
    if (Test-Path $resultsDir) { Remove-Item -Recurse -Force $resultsDir }
    pwsh -File $dispatcher -TestsPath tests -ResultsPath $resultsDir -JsonSummaryPath summary.json -MaxTestFiles 1 -IncludeIntegration false | Out-Null

    $sel = Join-Path $resultsDir 'pester-selected-files.txt'
    Test-Path $sel | Should -BeTrue
    $lines = Get-Content -LiteralPath $sel
    $lines.Count | Should -Be 1
  }
}
