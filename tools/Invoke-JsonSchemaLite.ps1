param(
  [Parameter(Mandatory)][string]$JsonPath,
  [Parameter(Mandatory)][string]$SchemaPath
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $JsonPath)) { Write-Error "JSON file not found: $JsonPath"; exit 2 }
if (-not (Test-Path -LiteralPath $SchemaPath)) { Write-Error "Schema file not found: $SchemaPath"; exit 2 }

try { $data = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Failed to parse JSON: $($_.Exception.Message)"; exit 2 }
try { $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Failed to parse schema: $($_.Exception.Message)"; exit 2 }

# Minimal validation: required fields, type kind for primitives, additionalProperties=false enforcement at top level only.
$errors = @()
if ($schema.required) {
  foreach ($r in $schema.required) {
    if ($data.PSObject.Properties.Name -notcontains $r) { $errors += "Missing required field '$r'" }
  }
}
if ($schema.properties) {
  foreach ($p in $schema.properties.PSObject.Properties) {
    $name = $p.Name; $spec = $p.Value
    if ($data.PSObject.Properties.Name -contains $name) {
      $val = $data.$name
      if ($spec.type -and $spec.type -in @('string','boolean','integer','object','array')) {
        switch ($spec.type) {
          'string' { if (-not ($val -is [string])) { $errors += "Field '$name' expected type string" } }
          'boolean' { if (-not ($val -is [bool])) { $errors += "Field '$name' expected type boolean" } }
          'integer' { if (-not ($val -is [int] -or $val -is [long])) { $errors += "Field '$name' expected integer" } }
          'object' { if (-not ($val -is [psobject])) { $errors += "Field '$name' expected object" } }
          'array' { if (-not ($val -is [System.Array])) { $errors += "Field '$name' expected array" } }
        }
      }
      if ($spec.const -and $val -ne $spec.const) { $errors += "Field '$name' const mismatch (expected $($spec.const))" }
    }
  }
}
if ($schema.additionalProperties -eq $false) {
  foreach ($actual in $data.PSObject.Properties.Name) {
    if ($schema.properties.PSObject.Properties.Name -notcontains $actual) { $errors += "Unexpected field '$actual'" }
  }
}

if ($errors) {
  $errors | ForEach-Object { Write-Host "[schema-lite] error: $_" }
  exit 3
}
Write-Host 'Schema-lite validation passed.'
exit 0
