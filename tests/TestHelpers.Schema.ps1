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

# Actual emitted run summary currently uses:
#   schema (e.g. 'compare-loop-run-summary-v1'), iterations, percentiles, requestedPercentiles,
#   optional histogram, diffs, errors, succeeded (some may be omitted in fast runs)
$script:JsonShapeSpecs['RunSummary'] = [pscustomobject]@{
  Required = @('schema','iterations','percentiles','requestedPercentiles')
  Optional = @('histogram','diffs','errors','succeeded','averageSeconds','totalSeconds')
  Types    = @{
    schema              = { param($v) $v -is [string] -and $v -like 'compare-loop-run-summary-*' }
    iterations          = { param($v) ((($v -is [int]) -or ($v -is [long]) -or ($v -is [double])) -and $v -ge 0) -or ($v -is [string] -and $v -match '^[0-9]+$') }
    percentiles         = { param($v) $v -is [pscustomobject] -or $v -is [hashtable] }
    requestedPercentiles= { param($v) $v -is [object[]] }
  histogram           = { param($v) -not $v -or $v -is [pscustomobject] -or $v -is [hashtable] -or $v -is [object[]] -or ($v -is [string]) }
    diffs               = { param($v) -not $v -or $v -is [int] -or $v -is [long] -or $v -is [double] -or ($v -is [string] -and $v -match '^[0-9]+$') }
    errors              = { param($v) -not $v -or $v -is [int] -or $v -is [long] -or $v -is [double] -or ($v -is [string] -and $v -match '^[0-9]+$') }
    succeeded           = { param($v) -not $v -or $v -is [bool] }
    averageSeconds      = { param($v) -not $v -or $v -is [double] -or $v -is [int] }
    totalSeconds        = { param($v) -not $v -or $v -is [double] -or $v -is [int] }
  }
}

# Snapshot schema (metrics-snapshot-v2 lines)
$script:JsonShapeSpecs['SnapshotV2'] = [pscustomobject]@{
  Required = @('schema','iteration','percentiles')
  Optional = @('requestedPercentiles','histogram','elapsedSeconds','diffs','errors')
  Types = @{
    schema              = { param($v) $v -eq 'metrics-snapshot-v2' }
  iteration           = { param($v) ($v -is [int] -or $v -is [long] -or ($v -is [string] -and $v -match '^[0-9]+$')) -and [int]$v -gt 0 }
    percentiles         = { param($v) $v -is [pscustomobject] -or $v -is [hashtable] }
    requestedPercentiles= { param($v) -not $v -or $v -is [object[]] }
  histogram           = { param($v) -not $v -or $v -is [pscustomobject] -or $v -is [hashtable] -or $v -is [object[]] -or ($v -is [string]) }
    elapsedSeconds      = { param($v) -not $v -or $v -is [double] -or $v -is [int] }
    diffs               = { param($v) -not $v -or $v -is [int] }
    errors              = { param($v) -not $v -or $v -is [int] }
  }
}

# Loop event NDJSON (loop-script-events-v1) meta/result/finalStatusEmitted lines
$script:JsonShapeSpecs['LoopEvent'] = [pscustomobject]@{
  Required = @('schema','timestamp','type')
  Optional = @('action','level','iterations','diffs','errors','succeeded','from','to','path')
  Types = @{
    schema     = { param($v) $v -eq 'loop-script-events-v1' }
  # Accept either already-parsed DateTime (some producers may emit [datetime]) or ISO-ish string
  timestamp  = { param($v) ($v -is [datetime]) -or ($v -is [string] -and $v.Length -ge 10) }
    type       = { param($v) $v -is [string] }
    action     = { param($v) -not $v -or $v -is [string] }
    level      = { param($v) -not $v -or $v -is [string] }
  iterations = { param($v) -not $v -or $v -is [int] -or $v -is [long] -or $v -is [double] }
  diffs      = { param($v) -not $v -or $v -is [int] -or $v -is [long] -or $v -is [double] }
  errors     = { param($v) -not $v -or $v -is [int] -or $v -is [long] -or $v -is [double] }
    succeeded  = { param($v) -not $v -or $v -is [bool] }
    from       = { param($v) -not $v -or $v -is [string] }
    to         = { param($v) -not $v -or $v -is [string] }
    path       = { param($v) -not $v -or $v -is [string] }
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

function Assert-NdjsonShapes {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Spec
  )
  if (-not (Test-Path -LiteralPath $Path)) { throw "Assert-NdjsonShapes: file not found: $Path" }
  $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
  $idx = 0
  foreach ($l in $lines) {
    $idx++
    if (-not $l.Trim()) { continue }
  try { $tmp = $l | ConvertFrom-Json -ErrorAction Stop } catch { throw ('Line {0} invalid JSON in {1}: {2}' -f $idx,$Path,$_.Exception.Message) }
    # Write object to temp file in memory (string) and reuse Assert-JsonShape logic by serializing again
    $json = $tmp | ConvertTo-Json -Depth 6
    $temp = [IO.Path]::GetTempFileName()
    try {
      Set-Content -LiteralPath $temp -Value $json -Encoding UTF8
      Assert-JsonShape -Path $temp -Spec $Spec | Out-Null
    } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
  return $true
}

# Note: No Export-ModuleMember call here; this helper is dot-sourced (not a module).
