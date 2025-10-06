Describe 'Invoke-PesterTests Include/Exclude patterns' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:dispatcher = Join-Path $repoRoot 'Invoke-PesterTests.ps1'
  }

  It 'honors IncludePatterns for a single file' {
    $resultsDir = Join-Path $TestDrive 'results-inc'
    $inc = @('Invoke-PesterTests.*.ps1')
    pwsh -File $script:dispatcher -TestsPath (Join-Path $repoRoot 'tests') -ResultsPath $resultsDir -IncludePatterns $inc -IncludeIntegration false | Out-Null
    $sel = Join-Path $resultsDir 'pester-selected-files.txt'
    Test-Path $sel | Should -BeTrue
    $lines = @(Get-Content -LiteralPath $sel)
    ($lines.Count -ge 1) | Should -BeTrue
    $allMatch = $true
    foreach ($l in $lines) { if (-not ($l -like '*Invoke-PesterTests.*.ps1')) { $allMatch = $false; break } }
    $allMatch | Should -BeTrue
  }

  It 'honors ExcludePatterns to remove files' {
    $resultsDir = Join-Path $TestDrive 'results-exc'
    $exc = @('PesterSummary.*.ps1')
    pwsh -File $script:dispatcher -TestsPath (Join-Path $repoRoot 'tests') -ResultsPath $resultsDir -ExcludePatterns $exc -IncludeIntegration false | Out-Null
    $sel = Join-Path $resultsDir 'pester-selected-files.txt'
    Test-Path $sel | Should -BeTrue
    $lines = @(Get-Content -LiteralPath $sel)
    $noneExcluded = $true
    foreach ($l in $lines) { if ($l -like '*PesterSummary.*.ps1') { $noneExcluded = $false; break } }
    $noneExcluded | Should -BeTrue
  }
}

