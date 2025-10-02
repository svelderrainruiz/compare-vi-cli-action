# Helper functions for asserting JSON document shapes used by loop and compare scripts.
# Lightweight alternative to full JSON schema libraries for fast Pester assertions.

Set-StrictMode -Version Latest

# Region: Shape Specifications
$Script:JsonShapeSpecs = @{
  'FinalStatus' = @{
    Required = @('schema','timestamp','iterations','diffs','errors','succeeded','averageSeconds','totalSeconds','percentiles','histogram','basePath','headPath','diffSummaryEmitted')
    Schema    = 'loop-final-status-v1'
    TypeMap   = @{
      schema             = 'string'
      timestamp          = 'string'
      iterations         = 'int'
      diffs              = 'int'
      errors             = 'int'
      succeeded          = 'bool'
      averageSeconds     = 'double'
      totalSeconds       = 'double'
      percentiles        = 'object'
      histogram          = 'object'
      basePath           = 'string'
      headPath           = 'string'
      diffSummaryEmitted = 'bool'
    }
  }
  'RunSummary' = @{
    Required = @('schema','timestamp','iterations','diffs','errors','succeeded','percentiles','histogram')
    Schema    = 'loop-run-summary-v1'
    TypeMap   = @{
      schema      = 'string'
      timestamp   = 'string'
      iterations  = 'int'
      diffs       = 'int'
      errors      = 'int'
      succeeded   = 'bool'
      percentiles = 'object'
      histogram   = 'object'
    }
  }
}

function Get-JsonTypeName {
  param([Parameter(Mandatory)][object]$Value)
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [bool]) { return 'bool' }
  if ($Value -is [int] -or $Value -is [long]) { return 'int' }
  if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) { return 'double' }
  if ($Value -is [string]) { return 'string' }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return 'object' }
  return 'object'
}

function Assert-JsonShape {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidateSet('FinalStatus','RunSummary')][string]$Spec
  )
  if (-not (Test-Path -LiteralPath $Path)) { throw "JSON file not found: $Path" }
  $raw = Get-Content -LiteralPath $Path -Raw
  $obj = $raw | ConvertFrom-Json
  $spec = $Script:JsonShapeSpecs[$Spec]
  if (-not $spec) { throw "Unknown spec '$Spec'" }

  $errors = @()
  $required = $spec.Required
  foreach ($k in $required) {
    if (-not ($obj.PSObject.Properties.Name -contains $k)) { $errors += "Missing required property '$k'" }
  }
  if ($spec.Schema -and $obj.schema -ne $spec.Schema) { $errors += "Expected schema '$($spec.Schema)' got '$($obj.schema)'" }
  foreach ($prop in $spec.TypeMap.Keys) {
    if (-not ($obj.PSObject.Properties.Name -contains $prop)) { continue }
    $actualType = Get-JsonTypeName -Value $obj.$prop
    $expectedType = $spec.TypeMap[$prop]
    # allow int where double expected (promote)
    if ($expectedType -eq 'double' -and $actualType -eq 'int') { continue }
    if ($actualType -ne $expectedType) { $errors += "Property '$prop' expected type $expectedType got $actualType" }
  }
  if ($errors.Count -gt 0) {
    throw "JSON shape assertion failed:`n - " + ($errors -join "`n - ")
  }
  return $obj
}

Export-ModuleMember -Function Assert-JsonShape -ErrorAction SilentlyContinue 2>$null | Out-Null
