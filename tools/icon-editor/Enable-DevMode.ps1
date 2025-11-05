#Requires -Version 7.0
[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$IconEditorRoot,
  [int[]]$Versions,
  [int[]]$Bitness,
  [string]$Operation = 'BuildPackage'
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
if ($Versions) {
  $invokeParams.Versions = $Versions
}
if ($Bitness) {
  $invokeParams.Bitness = $Bitness
}
if ($Operation) {
  $invokeParams.Operation = $Operation
}

$stateResult = Enable-IconEditorDevelopmentMode @invokeParams

if ($stateResult -is [System.Array]) {
  $state = $stateResult |
    Where-Object { $_ -is [psobject] -and $_.PSObject.Properties.Match('Path').Count -gt 0 } |
    Select-Object -Last 1
} else {
  $state = $stateResult
}

if (-not $state -or -not ($state.PSObject.Properties.Match('Path').Count -gt 0)) {
  throw 'Enable-IconEditorDevelopmentMode did not return a dev-mode state payload.'
}

Write-Host "Icon editor development mode enabled."
Write-Host ("State file: {0}" -f $state.Path)
Write-Host ("Updated at : {0}" -f $state.UpdatedAt)

$state

