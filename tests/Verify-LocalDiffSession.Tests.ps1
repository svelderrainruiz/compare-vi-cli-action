Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Verify-LocalDiffSession.ps1' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:toolPath = Join-Path $repoRoot 'tools' 'Verify-LocalDiffSession.ps1'
    Test-Path -LiteralPath $script:toolPath | Should -BeTrue
  }

  It 'produces a summary for normal mode using the stub' {
    $work = Join-Path $TestDrive 'lds-normal'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -UseStub -ResultsRoot $resultsDir -Mode 'normal'

    $result | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $result.resultsDir -PathType Container | Should -BeTrue
    Test-Path -LiteralPath $result.summary -PathType Leaf | Should -BeTrue

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.mode | Should -Be 'normal'
    $summary.runs.Count | Should -Be 1
    $summary.runs[0].cliSkipped | Should -BeFalse
    ($summary.runs[0].skipReason -eq $null -or [string]::IsNullOrWhiteSpace($summary.runs[0].skipReason)) | Should -BeTrue
  }

  It 'suppresses CLI in cli-suppressed mode' {
    $work = Join-Path $TestDrive 'lds-suppress'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -ResultsRoot $resultsDir -Mode 'cli-suppressed'

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.runs.Count | Should -Be 1
    $summary.runs[0].cliSkipped | Should -BeTrue
    $summary.runs[0].skipReason | Should -Be 'COMPAREVI_NO_CLI_CAPTURE'
  }

  It 'records sentinel skip on duplicate-window mode' {
    $work = Join-Path $TestDrive 'lds-dup'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -UseStub -ResultsRoot $resultsDir -Mode 'duplicate-window' -SentinelTtlSeconds 5

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.runs.Count | Should -Be 2
    $summary.runs[0].cliSkipped | Should -BeFalse
    $summary.runs[1].cliSkipped | Should -BeTrue
    $summary.runs[1].skipReason | Should -Match '^sentinel:'
  }
}
