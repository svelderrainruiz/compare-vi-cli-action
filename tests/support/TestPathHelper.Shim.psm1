Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$helperPath = Join-Path $testsRoot '_TestPathHelper.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
  throw "TestPathHelper shim could not locate script at '$helperPath'."
}

. $helperPath

# Export the helper used by multiple tests.
Export-ModuleMember -Function Resolve-RepoRoot
