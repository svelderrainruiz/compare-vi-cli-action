#Requires -Version 7.0
[CmdletBinding()]
param(
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

$state = Enable-IconEditorDevelopmentMode @invokeParams

Write-Host "Icon editor development mode enabled."
Write-Host ("State file: {0}" -f $state.Path)
Write-Host ("Updated at : {0}" -f $state.UpdatedAt)

$state

