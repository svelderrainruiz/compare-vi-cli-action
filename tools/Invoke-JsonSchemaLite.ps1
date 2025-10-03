param(
  [Parameter(Mandatory)][string]$JsonPath,
  [Parameter(Mandatory)][string]$SchemaPath
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $JsonPath)) { Write-Error "JSON file not found: $JsonPath"; exit 2 }
if (-not (Test-Path -LiteralPath $SchemaPath)) { Write-Error "Schema file not found: $SchemaPath"; exit 2 }

try { $data = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Failed to parse JSON: $($_.Exception.Message)"; exit 2 }
try { $schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { Write-Error "Failed to parse schema: $($_.Exception.Message)"; exit 2 }

function Test-TypeMatch {
  param($val,[string]$type,[string]$path)
  switch ($type) {
    'string' { if (-not ($val -is [string])) { return "Field '$path' expected type string" } }
    'boolean' { if (-not ($val -is [bool])) { return "Field '$path' expected type boolean" } }
    'integer' { if (-not ($val -is [int] -or $val -is [long])) { return "Field '$path' expected integer" } }
    'number'  { if (-not ($val -is [double] -or $val -is [float] -or $val -is [decimal] -or $val -is [int] -or $val -is [long])) { return "Field '$path' expected number" } }
    'object' { if (-not ($val -is [psobject])) { return "Field '$path' expected object" } }
    'array' { if (-not ($val -is [System.Array])) { return "Field '$path' expected array" } }
  }
  return $null
}

function Invoke-ValidateNode {
  param($node,$schemaNode,[string]$path)
  $errs = @()
  if ($schemaNode.required) {
    foreach ($r in $schemaNode.required) {
      if ($node.PSObject.Properties.Name -notcontains $r) { $errs += "Missing required field '$path$r'" }
    }
  }
  if ($schemaNode.properties) {
    foreach ($p in $schemaNode.properties.PSObject.Properties) {
      $name = $p.Name; $spec = $p.Value; $childPath = "$path$name."
      if ($node.PSObject.Properties.Name -contains $name) {
        $val = $node.$name
        if ($spec.type) {
          $tm = Test-TypeMatch -val $val -type $spec.type -path ("$path$name")
          if ($tm) { $errs += $tm; continue }
        }
  if ($spec.const -and $val -ne $spec.const) { $errs += "Field '$path$name' const mismatch (expected $($spec.const))" }
  if ($spec.enum -and $spec.enum.Count -gt 0 -and ($spec.enum -notcontains $val)) { $errs += "Field '$path$name' value '$val' not in enum [$($spec.enum -join ', ')]" }
  if ($spec.minimum -ne $null -and ($spec.type -in @('integer','number')) -and $val -lt $spec.minimum) { $errs += "Field '$path$name' value $val below minimum $($spec.minimum)" }
  if ($spec.maximum -ne $null -and ($spec.type -in @('integer','number')) -and $val -gt $spec.maximum) { $errs += "Field '$path$name' value $val above maximum $($spec.maximum)" }
        if ($spec.type -eq 'object' -and $spec.properties) {
          $errs += Invoke-ValidateNode -node $val -schemaNode $spec -path $childPath
        } elseif ($spec.type -eq 'array' -and $spec.items -and ($val -is [System.Array])) {
          for ($i=0; $i -lt $val.Count; $i++) {
            $itemVal = $val[$i]
            $tm2 = $null
            if ($spec.items.type) { $tm2 = Test-TypeMatch -val $itemVal -type $spec.items.type -path ("$path$name[$i]") }
            if ($tm2) { $errs += $tm2; continue }
            if ($spec.items.type -eq 'object' -and $spec.items.properties) {
              $errs += Invoke-ValidateNode -node $itemVal -schemaNode $spec.items -path ("$path$name[$i].")
            }
          }
        }
      }
    }
  }
  if ($schemaNode.additionalProperties -eq $false -and $schemaNode.properties) {
    foreach ($actual in $node.PSObject.Properties.Name) {
      if ($schemaNode.properties.PSObject.Properties.Name -notcontains $actual) { $errs += "Unexpected field '${path}$actual'" }
    }
  }
  return $errs
}

$errors = Invoke-ValidateNode -node $data -schemaNode $schema -path ''

if ($errors) {
  $errors | ForEach-Object { Write-Host "[schema-lite] error: $_" }
  exit 3
}
Write-Host 'Schema-lite validation passed.'
exit 0
