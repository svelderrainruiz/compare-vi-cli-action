<#
.SYNOPSIS
  Append a compact artifact path list to the job summary.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string[]]$Paths,
  [string]$Title = 'Artifacts'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

$lines = @("### $Title",'')
$any = $false
foreach ($p in $Paths) {
  if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p)) { $lines += ('- ' + $p); $any = $true }
}
if (-not $any) { $lines += '- (none found)' }
$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8

