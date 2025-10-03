# Deterministic HTML diff fragment regression test
# Tag: Unit
# Purpose: Ensure HTML diff summary is byte-for-byte stable and ordering is deterministic

Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/../module/CompareLoop/CompareLoop.psm1" -Force

Describe 'Invoke-IntegrationCompareLoop HTML diff summary determinism' -Tag 'Unit' {
  BeforeAll {
    $script:base = Join-Path $TestDrive 'VI1.vi'
    $script:head = Join-Path $TestDrive 'VI2.vi'
    Set-Content -Path $script:base -Value 'BASE_CONTENT'
    Set-Content -Path $script:head -Value 'HEAD_CONTENT'
  }

  It 'produces identical HTML fragment across multiple invocations with same inputs' {
    # Run the same scenario twice and verify byte-for-byte identity
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }  # Always diff
    
    $result1 = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 3 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -Quiet

    $result2 = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 3 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -Quiet

    $result1.DiffSummary | Should -Not -BeNullOrEmpty
    $result2.DiffSummary | Should -Not -BeNullOrEmpty
    $result1.DiffSummary | Should -BeExactly $result2.DiffSummary
  }

  It 'maintains deterministic list item order: Base, Head, Diff Iterations, Total Iterations' {
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }
    
    $result = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 5 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -Quiet

    $html = $result.DiffSummary
    $html | Should -Not -BeNullOrEmpty
    
    # Verify structure and ordering using regex
    $html | Should -Match '<h3>VI Compare Diff Summary</h3>'
    $html | Should -Match '<ul>'
    
    # Extract list items using regex (HTML uses <b> tags, not <strong>)
    $matches = [regex]::Matches($html, '<li><b>([^<]+)</b>')
    
    $matches.Count | Should -BeGreaterOrEqual 4
    $matches[0].Groups[1].Value | Should -Be 'Base:'
    $matches[1].Groups[1].Value | Should -Be 'Head:'
    $matches[2].Groups[1].Value | Should -Be 'Diff Iterations:'
    $matches[3].Groups[1].Value | Should -Be 'Total Iterations:'
  }

  It 'properly HTML-encodes special characters in file paths' {
    # Windows disallows < > " in file/directory names; simulate by embedding safe tokens then substituting
    $rawDirName = 'path & _LT_special_GT_ _DQ_chars_DQ_'
    $specialDir = Join-Path $TestDrive $rawDirName
    New-Item -ItemType Directory -Path $specialDir -Force | Out-Null

    $rawBase = 'base & file.vi'
    $rawHead = 'head < file >.vi'
    # Replace disallowed characters in actual filesystem paths but keep raw for assertion mapping
    $fsBaseName = $rawBase -replace '<','_LT_' -replace '>','_GT_' -replace '"','_DQ_'
    $fsHeadName = $rawHead -replace '<','_LT_' -replace '>','_GT_' -replace '"','_DQ_'
    $baseSpecial = Join-Path $specialDir $fsBaseName
    $headSpecial = Join-Path $specialDir $fsHeadName
    'A' | Set-Content -Path $baseSpecial -Encoding utf8
    'B' | Set-Content -Path $headSpecial -Encoding utf8
    
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }
    
    $result = Invoke-IntegrationCompareLoop -Base $baseSpecial -Head $headSpecial `
      -MaxIterations 2 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -Quiet

    $html = $result.DiffSummary
    
    # Verify HTML encoding (ampersand present, synthetic < > and " tokens encoded after substitution)
    $html | Should -Match '&amp;'  # ampersand encoded
    # We expect encoded placeholders for raw head path (simulate < and >)
    # Because actual filesystem lacked < >, we inject them into a virtual displayed path by reverse mapping in module output.
    $html | Should -Match '&lt;'   # less-than encoded
    $html | Should -Match '&gt;'   # greater-than encoded
    $html | Should -Match '&quot;' -Because 'double quote should be encoded if present'
    # Ensure unencoded raw sequences not present
    $html | Should -Not -Match 'base & file.vi'
    $html | Should -Not -Match 'head < file >.vi'
  }

  It 'does not emit HTML fragment when no diffs detected' {
    # All iterations return 0 (no diff)
    $executor = { param($cli,$b,$h,$lvArgs) return 0 }
    
    $result = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 5 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -Quiet

    $result.DiffCount | Should -Be 0
    $result.DiffSummary | Should -BeNullOrEmpty
  }

  It 'writes deterministic HTML file when path specified' {
    $summaryPath1 = Join-Path $TestDrive 'summary1.html'
    $summaryPath2 = Join-Path $TestDrive 'summary2.html'
    
    $executor = { param($cli,$b,$h,$lvArgs) return 1 }
    
    $result1 = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 4 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -DiffSummaryPath $summaryPath1 -Quiet

    $result2 = Invoke-IntegrationCompareLoop -Base $script:base -Head $script:head `
      -MaxIterations 4 -IntervalSeconds 0 -CompareExecutor $executor `
      -SkipValidation -PassThroughPaths -BypassCliValidation `
      -DiffSummaryFormat Html -DiffSummaryPath $summaryPath2 -Quiet

    Test-Path -LiteralPath $summaryPath1 | Should -BeTrue
    Test-Path -LiteralPath $summaryPath2 | Should -BeTrue
    
    $file1 = Get-Content -LiteralPath $summaryPath1 -Raw
    $file2 = Get-Content -LiteralPath $summaryPath2 -Raw
    
    $file1 | Should -BeExactly $file2
  }
}
