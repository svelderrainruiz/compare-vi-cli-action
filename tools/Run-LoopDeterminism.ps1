[CmdletBinding()]
param(
  [switch]$FailOnViolation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workflows = Get-ChildItem -Path (Join-Path (Get-Location).Path '.github/workflows') -Filter *.yml -File -ErrorAction SilentlyContinue
if (-not $workflows) {
  Write-Host 'No workflow files to lint.'
  exit 0
}

$pathsList = ($workflows | ForEach-Object { $_.FullName }) -join ';'

$args = @('-PathsList', $pathsList)
if ($FailOnViolation) { $args += '-FailOnViolation' }

& pwsh -NoLogo -NoProfile -File ./tools/Lint-LoopDeterminism.Shim.ps1 @args
exit $LASTEXITCODE
