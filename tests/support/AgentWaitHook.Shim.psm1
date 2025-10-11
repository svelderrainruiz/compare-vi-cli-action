Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure Agent-Wait functions are loaded first (required by the hook profile).
$agentWaitModule = Join-Path $PSScriptRoot 'AgentWait.Shim.psm1'
Import-Module $agentWaitModule -Force

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$hookScriptPath = Join-Path $repoRoot 'tools' 'Agent-WaitHook.Profile.ps1'
if (-not (Test-Path -LiteralPath $hookScriptPath -PathType Leaf)) {
  throw "Agent-WaitHook shim could not locate script at '$hookScriptPath'."
}

# Load hook profile logic into module scope so exports stay contained.
. $hookScriptPath

Export-ModuleMember -Function Enable-AgentWaitHook, Disable-AgentWaitHook
