[CmdletBinding()]
param()

Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path -Parent $PSCommandPath) 'VendorTools.psm1') -Force
$ErrorActionPreference = 'Stop'

$workspace = Get-Location

$alVersion = 'missing'
$alExe = Resolve-ActionlintPath
if ($alExe) {
  try {
    $alVersion = (& $alExe -version)
  } catch {
    $alVersion = 'unavailable'
  }
}

$nodeVer = 'missing'
$nodeCmd = Get-Command -Name 'node' -ErrorAction SilentlyContinue
if ($nodeCmd) {
  try {
    $nodeVer = $nodeCmd.FileVersionInfo.ProductVersion
  } catch {
    $nodeVer = 'unavailable'
  }
}

$npmVer = 'missing'
$npmCmd = Get-Command -Name 'npm.cmd' -ErrorAction SilentlyContinue
if (-not $npmCmd) {
  $npmCmd = Get-Command -Name 'npm' -ErrorAction SilentlyContinue
}
if ($npmCmd) {
  try {
    $npmRoot = Split-Path -Parent $npmCmd.Source
    $npmPkgPath = Join-Path -Path $npmRoot -ChildPath 'node_modules'
    $npmPkgPath = Join-Path -Path $npmPkgPath -ChildPath 'npm/package.json'
    $npmPkg = (Resolve-Path -LiteralPath $npmPkgPath -ErrorAction Stop).Path
    $npmJson = Get-Content -LiteralPath $npmPkg -Raw | ConvertFrom-Json
    if ($npmJson.version) { $npmVer = $npmJson.version } else { $npmVer = 'unavailable' }
  } catch {
    $npmVer = 'unavailable'
  }
}
$mdVer = Get-MarkdownlintCli2Version
if (-not $mdVer) { $mdVer = 'unavailable' }

if (-not $nodeVer) { $nodeVer = 'unavailable' }
if (-not $npmVer) { $npmVer = 'unavailable' }

Write-Host ("actionlint: {0}" -f $alVersion)
Write-Host ("node: {0}" -f $nodeVer)
Write-Host ("npm: {0}" -f $npmVer)
Write-Host ("markdownlint-cli2: {0}" -f $mdVer)
