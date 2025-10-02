<#
  TestHelpers.Schema.ps1
  Lightweight JSON schema/style assertion helpers for test reuse.

  Provides:
    Assert-JsonShape -Path <file> -Spec <name>

  Specs implemented initially:
    FinalStatus  -> final status JSON emitted by Run-AutonomousIntegrationLoop
    RunSummary   -> run summary JSON produced by compare loop

  Design goals:
    - Zero external dependencies
    - Fail fast with aggregated errors
    - Simple type predicates via scriptblocks
    - Optional properties supported
    - Tolerant of additional properties (forward compatible)
#>

Set-StrictMode -Version Latest

# Initialize spec dictionary safely under strict mode
if (-not (Get-Variable -Name JsonShapeSpecs -Scope Script -ErrorAction SilentlyContinue)) {
  $script:JsonShapeSpecs = @{}
}

$script:JsonShapeSpecs['FinalStatus'] = [pscustomobject]@{
  Required = @('schema','timestamp','iterations','diffs','errors','succeeded')
  Optional = @('averageSeconds','totalSeconds','percentiles','histogram','diffSummaryEmitted','basePath','headPath')
  Types    = @{
    schema            = { param($v) $v -is [string] -and $v -eq 'loop-final-status-v1' }
  timestamp         = { param($v) ($v -is [string] -or $v -is [datetime]) }
  iterations        = { param($v) (($v -is [int]) -or ($v -is [long]) -or ($v -is [double])) -and $v -ge 0 }
  diffs             = { param($v) (($v -is [int]) -or ($v -is [long]) -or ($v -is [double])) -and $v -ge 0 }
  errors            = { param($v) (($v -is [int]) -or ($v -is [long]) -or ($v -is [double])) -and $v -ge 0 }
    succeeded         = { param($v) $v -is [bool] }
    averageSeconds    = { param($v) -not $v -or $v -is [double] -or $v -is [int] }
    totalSeconds      = { param($v) -not $v -or $v -is [double] -or $v -is [int] }
    percentiles       = { param($v) -not $v -or ($v -is [hashtable] -or $v -is [pscustomobject]) }
    histogram         = { param($v) -not $v -or ($v -is [hashtable] -or $v -is [pscustomobject]) }
    diffSummaryEmitted= { param($v) -not $v -or $v -is [bool] }
    basePath          = { param($v) -not $v -or $v -is [string] }
    headPath          = { param($v) -not $v -or $v -is [string] }
  }
}

$script:JsonShapeSpecs['RunSummary'] = [pscustomobject]@{
  Required = @(
    'schemaVersion','startedUtc','completedUtc','durationSeconds',
    'success','diffs','errors','iterations'
  )
  Optional = @('percentiles','histogram','message')
  Types    = @{
    schemaVersion    = { param($v) $v -eq 1 }
    startedUtc       = { param($v) $v -is [string] -and $v.Length -ge 10 }
    completedUtc     = { param($v) $v -is [string] -and $v.Length -ge 10 }
    durationSeconds  = { param($v) $v -is [double] -or $v -is [int] }
    success          = { param($v) $v -is [bool] }
    diffs            = { param($v) $v -is [int] -and $v -ge 0 }
    errors           = { param($v) $v -is [int] -and $v -ge 0 }
    iterations       = { param($v) $v -is [int] -and $v -ge 0 }
    percentiles      = { param($v) -not $v -or ($v -is [hashtable] -or $v -is [pscustomobject]) }
    histogram        = { param($v) -not $v -or ($v -is [hashtable] -or $v -is [pscustomobject]) }
    message          = { param($v) -not $v -or $v -is [string] }
  }
}

function Assert-JsonShape {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Spec
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Assert-JsonShape: file not found: $Path"
  }
  if (-not $script:JsonShapeSpecs.ContainsKey($Spec)) {
    throw "Assert-JsonShape: unknown spec '$Spec'"
  }
  $jsonText = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  try { $obj = $jsonText | ConvertFrom-Json -ErrorAction Stop } catch {
    throw "Assert-JsonShape: invalid JSON in $Path : $($_.Exception.Message)"
  }
  $specDef = $script:JsonShapeSpecs[$Spec]
  $errors = New-Object System.Collections.Generic.List[string]

  foreach ($key in $specDef.Required) {
    if (-not ($obj.PSObject.Properties.Name -contains $key)) {
      $errors.Add("missing required property '$key'")
    }
  }

  foreach ($prop in $obj.PSObject.Properties) {
    $name = $prop.Name
    $val  = $prop.Value
    $isKnown = $specDef.Required -contains $name -or $specDef.Optional -contains $name -or $specDef.Types.ContainsKey($name)
    if ($isKnown -and $specDef.Types.ContainsKey($name)) {
      $predicate = $specDef.Types[$name]
      $ok = & $predicate $val
      if (-not $ok) { $errors.Add("property '$name' failed type predicate (value='$val')") }
    }
  }

  if ($errors.Count -gt 0) {
    $msg = "Assert-JsonShape FAILED for spec '$Spec' on file '$Path':`n - " + ($errors -join "`n - ")
    throw $msg
  }
  return $true
}

# Note: No Export-ModuleMember call here; this helper is dot-sourced (not a module).
