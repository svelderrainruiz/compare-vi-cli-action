Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Local Agent Handoff' -Tag 'Unit' {
  It 'prints AGENT_HANDOFF.txt' {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Test-Path -LiteralPath (Join-Path $repoRoot 'AGENT_HANDOFF.txt') | Should -BeTrue
    $script = Join-Path $repoRoot 'tools' 'Print-AgentHandoff.ps1'
    Test-Path -LiteralPath $script | Should -BeTrue
    $null = & $script -ApplyToggles
    $env:LV_SUPPRESS_UI | Should -Be '1'
    $env:WATCH_RESULTS_DIR | Should -Match 'tests/results/_watch'
  }
}
