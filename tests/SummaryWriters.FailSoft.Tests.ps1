Describe 'Summary writers are fail-soft' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:det = Join-Path $repoRoot 'tools/Write-DeterminismSummary.ps1'
    $script:rid = Join-Path $repoRoot 'tools/Write-RunnerIdentity.ps1'
  }

  It 'Write-DeterminismSummary exits 0 when GITHUB_STEP_SUMMARY is unset' {
    $env:GITHUB_STEP_SUMMARY = $null
    pwsh -File $script:det
    $LASTEXITCODE | Should -Be 0
  }

  It 'Write-RunnerIdentity exits 0 when GITHUB_STEP_SUMMARY is unset' {
    $env:GITHUB_STEP_SUMMARY = $null
    pwsh -File $script:rid -SampleId 'test-sample'
    $LASTEXITCODE | Should -Be 0
  }
}

