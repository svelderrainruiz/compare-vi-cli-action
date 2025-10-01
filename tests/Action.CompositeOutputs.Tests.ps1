# Requires -Version 5.1
# Pester tests validating composite action script-level behavior via direct function invocation
# (We cannot invoke the composite action YAML directly in-process, but we can emulate what it does.)

BeforeAll {
  $here = Split-Path -Parent $PSCommandPath
  $root = Resolve-Path (Join-Path $here '..')
  . (Join-Path $root 'scripts' 'CompareVI.ps1')
}

Describe 'Composite action output shape (emulated)' -Tag 'Unit' {
  It 'produces all expected duration-related outputs' {
    # Arrange: create two temp files to act as .vi placeholders
    $vis = Join-Path $TestDrive 'vis'
    New-Item -ItemType Directory -Path $vis -Force | Out-Null
    $a = Join-Path $vis 'a.vi'
    $b = Join-Path $vis 'b.vi'
    New-Item -ItemType File -Path $a -Force | Out-Null
    New-Item -ItemType File -Path $b -Force | Out-Null

    # Mock Resolve-Cli so we don't depend on real installation
    $canonical = 'C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe'
    Mock -CommandName Resolve-Cli -MockWith { $canonical }

    # Act
    $res = Invoke-CompareVI -Base $a -Head $b -FailOnDiff:$false -Executor { 1 }

    # Assert
    $res | Should -Not -BeNullOrEmpty
    $res.CompareDurationSeconds | Should -BeGreaterOrEqual 0
    $res.CompareDurationNanoseconds | Should -BeGreaterOrEqual 0
    $res.CompareDurationNanoseconds | Should -BeGreaterThan 0  # expect non-zero elapsed even if near instantaneous
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue
  }

  It 'writes both duration outputs to a mock GITHUB_OUTPUT file' {
    $vis = Join-Path $TestDrive 'vis'
    New-Item -ItemType Directory -Path $vis -Force | Out-Null
    $a = Join-Path $vis 'a.vi'
    $b = Join-Path $vis 'b.vi'
    New-Item -ItemType File -Path $a -Force | Out-Null
    New-Item -ItemType File -Path $b -Force | Out-Null

    $canonical = 'C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe'
    Mock -CommandName Resolve-Cli -MockWith { $canonical }

    $outPath = Join-Path $TestDrive 'gout.txt'
    $sumPath = Join-Path $TestDrive 'summary.md'
    $res = Invoke-CompareVI -Base $a -Head $b -GitHubOutputPath $outPath -GitHubStepSummaryPath $sumPath -FailOnDiff:$false -Executor { 1 }

    $content = Get-Content $outPath -Raw
    $content | Should -Match 'compareDurationSeconds='
    $content | Should -Match 'compareDurationNanoseconds='
    $content | Should -Match 'diff=true'
    (Get-Content $sumPath -Raw) | Should -Match 'Duration \(s\):'
    (Get-Content $sumPath -Raw) | Should -Match 'Duration \(ns\):'
  }
}
