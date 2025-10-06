<#
.SYNOPSIS
  Generate a sample_id for workflow_dispatch runs.
.DESCRIPTION
  Emits a compact, readable sample id by default (ts-YYYYMMDD-HHMMSS-XXXX).
  Can emit GUID with -Format guid.
.PARAMETER Prefix
  Optional prefix to add before the id.
.PARAMETER Format
  'ts' (default) or 'guid'.
.OUTPUTS
  Writes the id to stdout and sets GITHUB_OUTPUT 'sample_id' if available.
#>
[CmdletBinding()]
param(
  [string]$Prefix,
  [ValidateSet('ts','guid')][string]$Format = 'ts'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-TsId {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $rnd = -join ((48..57 + 97..122) | Get-Random -Count 4 | ForEach-Object {[char]$_})
  "ts-$ts-$rnd"
}

$id = if ($Format -eq 'guid') { [guid]::NewGuid().ToString() } else { New-TsId }
if ($Prefix) { $id = "$Prefix$id" }

if ($env:GITHUB_OUTPUT) { "sample_id=$id" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8 }
Write-Output $id

