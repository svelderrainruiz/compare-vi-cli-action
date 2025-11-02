#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][bool]$ExpectedActive,
  [string]$RepoRoot,
  [string]$IconEditorRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $PSCommandPath
$modulePath = Join-Path $scriptDirectory 'IconEditorDevMode.psm1'
Import-Module $modulePath -Force

$invokeParams = @{}
if ($RepoRoot) {
  $invokeParams.RepoRoot = $RepoRoot
}
if ($IconEditorRoot) {
  $invokeParams.IconEditorRoot = $IconEditorRoot
}

$result = Test-IconEditorDevelopmentMode @invokeParams
$entries = $result.Entries
$present = $entries | Where-Object { $_.Present }

if ($present.Count -eq 0) {
  Write-Error "No LabVIEW installations were detected for development mode verification. Expected to find LabVIEW 2021 (32-bit and/or 64-bit)."
  exit 1
}

$targetState = if ($ExpectedActive) { 'enabled' } else { 'disabled' }
Write-Host ("Verifying icon editor development mode is {0}..." -f $targetState)

$failed = @()
foreach ($entry in $present) {
  $status = if ($entry.ContainsIconEditorPath) { 'contains icon editor path' } else { 'does not contain icon editor path' }
  Write-Host ("- LabVIEW {0} ({1}-bit): {2}" -f $entry.Version, $entry.Bitness, $status)
  $isMatch = ($entry.ContainsIconEditorPath -eq $ExpectedActive)
  if (-not $isMatch) {
    $failed += $entry
  }
}

if ($failed.Count -gt 0) {
  $failText = $failed | ForEach-Object {
    "LabVIEW {0} ({1}-bit)" -f $_.Version, $_.Bitness
  }
  throw ("Icon editor development mode expected '{0}' but mismatched targets: {1}" -f $targetState, ($failText -join ', '))
}

Write-Host "Icon editor development mode verification succeeded."
$result

