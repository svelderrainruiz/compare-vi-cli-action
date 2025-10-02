Set-StrictMode -Version Latest

# Ensure helper is dot-sourced using path relative to test directory
. (Join-Path $PSScriptRoot 'TestHelpers.Schema.ps1')

Describe 'Schema Export Type Inference' -Tag 'Unit' {
  It 'adds type for simple predicates when -InferTypes used' {
    . (Join-Path $PSScriptRoot 'TestHelpers.Schema.ps1')
    $outDir = Join-Path $TestDrive 'schemas'
    Export-JsonShapeSchemas -OutputDirectory $outDir -Overwrite -InferTypes | Out-Null
    $runSummarySchemaPath = Join-Path $outDir 'RunSummary.schema.json'
    Test-Path $runSummarySchemaPath | Should -BeTrue
    $schema = Get-Content -LiteralPath $runSummarySchemaPath -Raw | ConvertFrom-Json
  # Ensure representative properties gained type info (string scalar)
  $schema.properties.schema.type | Should -Be 'string'
  # iterations predicate allows string/integer/number so we expect array containing these
  ($schema.properties.iterations.type | Sort-Object) | Should -Be @('integer','number','string')
  $schema.properties.succeeded.type | Should -Be 'boolean'
  }
  It 'omits type when inference finds nothing' {
    . (Join-Path $PSScriptRoot 'TestHelpers.Schema.ps1')
    $outDir = Join-Path $TestDrive 'schemas2'
    Export-JsonShapeSchemas -OutputDirectory $outDir -Overwrite -InferTypes | Out-Null
    $path = Join-Path $outDir 'LoopEvent.schema.json'
    $schema = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  # action predicate is -not $v -or $v -is [string] so should infer string
  $schema.properties.action.type | Should -Be 'string'
  }
}
