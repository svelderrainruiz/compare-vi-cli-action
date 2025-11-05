#Requires -Version 7.0

param(
  [string]$Operation = 'applyVipc',
  [int]$RequiredVersion,
  [int]$RequiredBitness
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
  $repoRoot = (Get-Location).Path
}

$vendorModule = Join-Path $repoRoot 'tools' 'VendorTools.psm1'
if (-not (Test-Path -LiteralPath $vendorModule -PathType Leaf)) {
  throw "Vendor tools module not found at '$vendorModule'."
}

Import-Module $vendorModule -Force

$targets = Get-LabVIEWOperationTargets -Operation $Operation -RepoRoot $repoRoot
if (-not $targets -or $targets.Count -eq 0) {
  Write-Warning ("No LabVIEW targets defined for operation '{0}'. Check configs/labview-targets.json." -f $Operation)
  return
}

Write-Host ("Targets for '{0}':" -f $Operation) -ForegroundColor Cyan
$targets | ForEach-Object {
  Write-Host ("  - Version {0}, {1}-bit" -f $_.Version, $_.Bitness)
}

if ($PSBoundParameters.ContainsKey('RequiredVersion')) {
  if (-not $PSBoundParameters.ContainsKey('RequiredBitness')) {
    throw 'Specify both -RequiredVersion and -RequiredBitness to enforce a target check.'
  }

  $match = $targets | Where-Object { $_.Version -eq $RequiredVersion -and $_.Bitness -eq $RequiredBitness }
  if (-not $match) {
    throw ("Operation '{0}' does not include LabVIEW {1} ({2}-bit). Update configs/labview-targets.json before continuing." -f $Operation, $RequiredVersion, $RequiredBitness)
  }
}
