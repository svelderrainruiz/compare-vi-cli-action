#Requires -Version 7.0
<#
.SYNOPSIS
  Helper wrapper for dot-sourcing lint task that tolerates missing script.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Get-Location
$lintScript = Join-Path $workspace.Path 'tools/Lint-DotSourcing.ps1'

if (Test-Path -LiteralPath $lintScript -PathType Leaf) {
  & pwsh -NoLogo -NoProfile -File $lintScript -WarnOnly
  exit $LASTEXITCODE
}

Write-Warning 'tools/Lint-DotSourcing.ps1 not found; skipping dot-sourcing lint.'
exit 0

