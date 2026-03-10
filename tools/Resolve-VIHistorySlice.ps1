#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SelectorPath,

  [string]$OutputPath,
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'VIHistorySlice.psm1'
Import-Module $modulePath -Force

$manifest = Resolve-VIHistorySliceManifest -SelectorPath $SelectorPath
$manifestJson = $manifest | ConvertTo-Json -Depth 16

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $outputResolved = [System.IO.Path]::GetFullPath($OutputPath)
  } else {
    $outputResolved = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))
  }
  $outputParent = Split-Path -Parent $outputResolved
  if ($outputParent -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
  }
  Set-Content -LiteralPath $outputResolved -Value $manifestJson -Encoding utf8
}

if ($PassThru) {
  $manifest
} else {
  $manifestJson
}
