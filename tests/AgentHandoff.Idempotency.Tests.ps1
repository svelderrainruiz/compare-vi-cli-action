Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Agent Handoff standing priority reuse' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $path = Join-Path $repoRoot 'tools' 'Print-AgentHandoff.ps1'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Print-AgentHandoff.ps1 not found at $path"
    }
    $script:HandOffScriptPath = $path
  }

  It 'does not invoke standing priority sync when cache is healthy' {
    $scriptPath = $script:HandOffScriptPath
    $null = & $scriptPath -ApplyToggles 2>&1
    $result2 = & $scriptPath -ApplyToggles 2>&1

    $joined = ($result2 | Out-String)

    $joined | Should -Not -Match '\[priority\]'
    $joined | Should -Not -Match 'Standing priority sync skipped'
  }
}
