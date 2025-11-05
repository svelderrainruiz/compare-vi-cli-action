#Requires -Version 7.0

param(
  [string]$Operation = 'applyVipc',
  [switch]$Require2023x64
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
} else {
  Write-Host ("Targets for '{0}':" -f $Operation) -ForegroundColor Cyan
  $targets | ForEach-Object {
    Write-Host ("  - Version {0}, {1}-bit" -f $_.Version, $_.Bitness)
  }

  if ($Require2023x64.IsPresent) {
    $hasTarget = $targets | Where-Object { $_.Version -eq 2023 -and $_.Bitness -eq 64 }
    if (-not $hasTarget) {
      throw "Operation '$Operation' does not include LabVIEW 2023 (64-bit). Update configs/labview-targets.local.json before continuing."
    }
  }
}

