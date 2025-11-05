#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$Version,
  [int]$Bitness = 64,
  [string]$RepoRoot,
  [string]$IconEditorRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
  $RepoRoot = (git -C (Get-Location).Path rev-parse --show-toplevel 2>$null)
  if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
  }
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if (-not $IconEditorRoot) {
  $IconEditorRoot = Join-Path $RepoRoot 'vendor' 'icon-editor'
}
$IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path

$modulePath = Join-Path $RepoRoot 'tools' 'icon-editor' 'IconEditorDevMode.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
  throw "IconEditorDevMode module not found at '$modulePath'."
}

Import-Module $modulePath -Force

try {
  $result = Assert-IconEditorDevelopmentToken `
    -RepoRoot $RepoRoot `
    -IconEditorRoot $IconEditorRoot `
    -Versions @($Version) `
    -Bitness @($Bitness) `
    -Operation 'TokenCheck'
} catch {
  Write-Error $_.Exception.Message
  exit 1
}

$entry = $result.Entries | Where-Object { $_.Version -eq $Version -and $_.Bitness -eq $Bitness } | Select-Object -First 1
if (-not $entry) {
  Write-Warning ("No entry reported for LabVIEW {0} ({1}-bit) even though the assertion passed." -f $Version, $Bitness)
} else {
  Write-Host ("Token check passed for LabVIEW {0} ({1}-bit)." -f $Version, $Bitness) -ForegroundColor Green
  Write-Host ("  INI Path : {0}" -f ($entry.LabVIEWIniPath ?? '<unknown>'))
  Write-Host ("  Token    : {0}" -f ($entry.TokenValue ?? '<empty>'))
}

exit 0
