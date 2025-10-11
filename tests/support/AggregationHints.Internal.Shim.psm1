Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$aggregationScript = Join-Path $repoRoot 'scripts' 'AggregationHints.Internal.ps1'
if (-not (Test-Path -LiteralPath $aggregationScript -PathType Leaf)) {
  throw "AggregationHints shim could not locate script at '$aggregationScript'."
}

# Load helper functions into module scope without leaking to global scope.
. $aggregationScript

Export-ModuleMember -Function Get-AggregationHintsBlock
