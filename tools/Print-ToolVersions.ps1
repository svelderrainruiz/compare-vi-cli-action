[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = Get-Location
$alPath = Join-Path $workspace.Path 'bin/actionlint'
$alVersion = 'n/a'
if (Test-Path -LiteralPath $alPath) {
  try { $alVersion = & $alPath -version } catch {}
}

function Get-VersionSafe {
  param([string]$Command,[string[]]$Args)
  try {
    $result = & $Command @Args
    if ($null -eq $result) { return '' }
    return [string]$result
  } catch {
    return ''
  }
}

$nodeVer = Get-VersionSafe -Command 'node' -Args '-v'
$npmVer  = Get-VersionSafe -Command 'npm'  -Args '-v'
$mdVer = ''
# Prefer locally installed binary to avoid npx download prompts
$mdLocal = Join-Path $workspace.Path 'node_modules/.bin/markdownlint-cli2'
if (Test-Path -LiteralPath $mdLocal) {
  $mdVer = Get-VersionSafe -Command $mdLocal -Args '--version'
} else {
  # Fall back to package.json metadata before hitting npx
  try {
    $pkgJson = Get-Content -LiteralPath (Join-Path $workspace.Path 'package.json') -Raw | ConvertFrom-Json
    $declared = $pkgJson.devDependencies.'markdownlint-cli2'
    if ($declared) { $mdVer = "declared $declared" }
  } catch { }
  if (-not $mdVer) {
    $mdVer = Get-VersionSafe -Command 'npx'  -Args @('--yes','markdownlint-cli2','--version')
  }
}

Write-Host ("actionlint: {0}" -f $alVersion)
Write-Host ("node: {0}" -f $nodeVer)
Write-Host ("npm: {0}" -f $npmVer)
Write-Host ("markdownlint-cli2: {0}" -f $mdVer)
