Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Watch-Pester flaky recovery integration' -Tag 'FlakyDemo' {
  It 'recovers a flaky failure and marks classification improved' {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Push-Location $repoRoot
    try {
      $delta = Join-Path $repoRoot 'tests/results/flaky-recovery-delta.json'
      if (Test-Path $delta) { Remove-Item -LiteralPath $delta -Force }
      $env:ENABLE_FLAKY_DEMO = '1'
      $state = Join-Path $repoRoot 'tests/results/flaky-demo-state.txt'
      if (Test-Path $state) { Remove-Item -LiteralPath $state -Force }
      $watch = Join-Path $repoRoot 'tools/Watch-Pester.ps1'
      & pwsh -NoLogo -NoProfile -File $watch -SingleRun -Tag FlakyDemo -RerunFailedAttempts 2 -DeltaJsonPath $delta -Quiet | Out-Null
    } finally { Pop-Location }

    Test-Path $delta | Should -BeTrue
    $json = Get-Content -LiteralPath $delta -Raw | ConvertFrom-Json
    $json.flaky.enabled | Should -BeTrue
  $json.flaky.recoveredAfter | Should -Be 1 -Because 'Flaky recovery should occur on first retry'
  $json.classification | Should -Be 'improved' -Because 'Classification forced improved on recovery'
  $json.flaky.initialFailedFiles | Should -BeGreaterOrEqual 1 -Because 'At least one failing file expected initially'
  ($json.flaky.initialFailedFileNames | Measure-Object).Count | Should -Be $json.flaky.initialFailedFiles -Because 'Names array count matches initialFailedFiles'
  }
}
