Describe 'Invoke-IntegrationCompareLoop HTML diff summary generation' -Tag 'Unit' {
  # We simulate compare executions by injecting a CompareExecutor that returns exit codes.
  # Exit code 1 => diff; 0 => no diff.

  It 'emits HTML diff summary and writes file when diffs detected' {
    $base = Join-Path $TestDrive 'base.vi'
    $head = Join-Path $TestDrive 'head.vi'
    Set-Content -Path $base -Value 'BASE'
    Set-Content -Path $head -Value 'HEAD'

    $summaryPath = Join-Path $TestDrive 'diff-summary.html'
    # Single-iteration run: always return exit code 1 to trigger diff summary generation
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }

  $result = Invoke-IntegrationCompareLoop -Base $base -Head $head -MaxIterations 1 -IntervalSeconds 0 -CompareExecutor $executor -SkipValidation -PassThroughPaths -BypassCliValidation -DiffSummaryFormat Html -DiffSummaryPath $summaryPath

    $result.DiffCount | Should -Be 1
    $result.DiffSummary | Should -Match '<h3>VI Compare Diff Summary</h3>'
    $result.DiffSummary | Should -Match '<ul>'
    Test-Path -LiteralPath $summaryPath | Should -BeTrue
    $file = Get-Content -LiteralPath $summaryPath -Raw
    $file | Should -Match 'Diff Iterations'
  }

  It 'does not emit HTML diff summary when no diffs detected' {
    $base = Join-Path $TestDrive 'base2.vi'
    $head = Join-Path $TestDrive 'head2.vi'
    Set-Content -Path $base -Value 'SAME'
    Set-Content -Path $head -Value 'SAME'

    $summaryPath = Join-Path $TestDrive 'diff-summary-none.html'
    $executor = { param($cli,$b,$h,$lvArgs) return 0 }

  $result = Invoke-IntegrationCompareLoop -Base $base -Head $head -MaxIterations 1 -IntervalSeconds 0 -CompareExecutor $executor -SkipValidation -PassThroughPaths -BypassCliValidation -DiffSummaryFormat Html -DiffSummaryPath $summaryPath

    $result.DiffCount | Should -Be 0
    $result.DiffSummary | Should -Be $null
    Test-Path -LiteralPath $summaryPath | Should -BeFalse
  }

  It 'HTML diff summary encodes special characters in paths' {
    # Create paths with ampersand to ensure HTML encoding occurs (& -> &amp;)
    $dir = Join-Path $TestDrive 'html-encoding'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $base = Join-Path $dir 'base & a.vi'
    $head = Join-Path $dir 'head & b.vi'
    Set-Content -Path $base -Value 'A'
    Set-Content -Path $head -Value 'B'
    $summaryPath = Join-Path $TestDrive 'diff-summary-encoding.html'
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }
  $result = Invoke-IntegrationCompareLoop -Base $base -Head $head -MaxIterations 1 -IntervalSeconds 0 -CompareExecutor $executor -SkipValidation -PassThroughPaths -BypassCliValidation -DiffSummaryFormat Html -DiffSummaryPath $summaryPath
    $result.DiffSummary | Should -Match '&amp;'
    $file = Get-Content -LiteralPath $summaryPath -Raw
    $file | Should -Match '&amp;'
  }
}
