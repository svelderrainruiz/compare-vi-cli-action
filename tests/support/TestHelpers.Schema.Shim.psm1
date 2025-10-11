Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$schemaHelperPath = Join-Path $testsRoot 'TestHelpers.Schema.ps1'
if (-not (Test-Path -LiteralPath $schemaHelperPath -PathType Leaf)) {
  throw "TestHelpers.Schema shim could not locate script at '$schemaHelperPath'."
}

# Load helper definitions into module scope.
. $schemaHelperPath

Export-ModuleMember -Function Assert-JsonShape, Assert-NdjsonShapes, Export-JsonShapeSchemas
