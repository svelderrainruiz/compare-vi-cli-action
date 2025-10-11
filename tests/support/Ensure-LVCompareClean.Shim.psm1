Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$ensureScriptPath = Join-Path $repoRoot 'scripts' 'Ensure-LVCompareClean.ps1'
if (-not (Test-Path -LiteralPath $ensureScriptPath -PathType Leaf)) {
  throw "Ensure-LVCompareClean shim could not locate script at '$ensureScriptPath'."
}

. $ensureScriptPath

Export-ModuleMember -Function Get-LVCompareProcesses, Stop-LVCompareProcesses, Get-LabVIEWProcesses, Stop-LabVIEWProcesses
