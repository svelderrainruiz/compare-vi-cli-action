Set-StrictMode -Version Latest

. "$PSScriptRoot/TestHelpers.Schema.ps1"

Describe 'Compare-JsonShape diff helper' -Tag 'Unit' {
  It 'detects missing required properties and value diffs' {
    $base = Join-Path $TestDrive 'base.json'
    $cand = Join-Path $TestDrive 'cand.json'
    # Base has required + some optional
    $baseObj = @{ schema='loop-final-status-v1'; timestamp='2024-01-01T00:00:00Z'; iterations=5; diffs=1; errors=0; succeeded=$true }
    $candObj = @{ schema='loop-final-status-v1'; timestamp='2024-01-01T00:00:00Z'; iterations=7; diffs=0; succeeded=$true } # missing errors, value differences iterations/diffs
    $baseObj | ConvertTo-Json | Set-Content -LiteralPath $base -Encoding UTF8
    $candObj | ConvertTo-Json | Set-Content -LiteralPath $cand -Encoding UTF8
    $r = Compare-JsonShape -BaselinePath $base -CandidatePath $cand -Spec FinalStatus -Strict
    $r.MissingInCandidate | Should -Contain 'errors'
    # errors not missing in baseline
    $r.MissingInBaseline | Should -Be @()
    # Strict unexpected none
    $r.UnexpectedInCandidate | Should -Be @()
    # Value diffs should include iterations and diffs
    ($r.ValueDifferences | Where-Object Property -eq 'iterations').Count | Should -Be 1
    ($r.ValueDifferences | Where-Object Property -eq 'diffs').Count | Should -Be 1
  }
}
