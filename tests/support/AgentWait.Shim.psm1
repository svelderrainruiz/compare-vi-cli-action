Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$agentWaitPath = Join-Path $repoRoot 'tools' 'Agent-Wait.ps1'
if (-not (Test-Path -LiteralPath $agentWaitPath -PathType Leaf)) {
  throw "Agent-Wait shim could not locate script at '$agentWaitPath'."
}

# Load the script inside module scope so helper functions stay private.
. $agentWaitPath

Export-ModuleMember -Function Start-AgentWait, End-AgentWait
