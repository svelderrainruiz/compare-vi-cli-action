Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Child process snapshot schema sanity' -Tag 'Unit' {
  It 'emits a well-formed child-procs snapshot JSON' {
    $repoRoot = (Get-Location).Path
    $results = Join-Path $repoRoot 'tests/results/schema-child'
    New-Item -ItemType Directory -Path $results -Force | Out-Null
    $script = Join-Path $repoRoot 'tools/Debug-ChildProcesses.ps1'
    Test-Path -LiteralPath $script | Should -BeTrue
    & pwsh -NoLogo -NoProfile -File $script -ResultsDir $results | Out-Null
    $outPath = Join-Path $repoRoot 'tests/results/_agent/child-procs.json'
    Test-Path -LiteralPath $outPath | Should -BeTrue
    $json = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json -Depth 6
    $json | Should -Not -BeNullOrEmpty
    ($json.PSObject.Properties.Name -contains 'schema') | Should -BeTrue
    ($json.PSObject.Properties.Name -contains 'at') | Should -BeTrue
    ($json.PSObject.Properties.Name -contains 'groups') | Should -BeTrue
  }
}
