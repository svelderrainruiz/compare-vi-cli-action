#Requires -Version 7.0

param(
  [string]$FixturePath,
  [string]$ResultsRoot,
  [object]$ExpectedVersion,
  [switch]$KeepExtract
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try {
    return (git -C $StartPath rev-parse --show-toplevel 2>$null).Trim()
  } catch {
    return $StartPath
  }
}

function Convert-ToOrderedHashtable {
  param([System.Collections.IDictionary]$Table)
  if (-not $Table) {
    return $null
  }

  $ordered = [ordered]@{}
  foreach ($key in $Table.Keys) {
    $ordered[$key] = $Table[$key]
  }
  return $ordered
}

$repoRoot = Resolve-RepoRoot

if (-not $FixturePath) {
  $FixturePath = Join-Path $repoRoot 'tests' 'fixtures' 'icon-editor' 'ni_icon_editor-1.4.1.948.vip'
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
  throw "Fixture VI Package not found at '$FixturePath'. Ensure the repository fixture exists or supply -FixturePath."
}

if (-not $ResultsRoot) {
  $ResultsRoot = Join-Path $repoRoot 'tests' 'results' '_agent' 'icon-editor-simulate'
}

$ResultsRoot = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $ResultsRoot -Force)).Path
$resolvedFixture = (Resolve-Path -LiteralPath $FixturePath).Path

$extractRoot = Join-Path $ResultsRoot '__fixture_extract'
if (Test-Path -LiteralPath $extractRoot) {
  Remove-Item -LiteralPath $extractRoot -Recurse -Force
}

Expand-Archive -Path $resolvedFixture -DestinationPath $extractRoot -Force

$specPath = Join-Path $extractRoot 'spec'
if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
  throw "Fixture spec not found at '$specPath'. The fixture appears to be invalid."
}

$specContent = Get-Content -LiteralPath $specPath
$versionLine = $specContent | Where-Object { $_ -match '^Version="([^"]+)"' } | Select-Object -First 1
if (-not $versionLine) {
  throw "Unable to parse version from fixture spec at '$specPath'."
}

$fixtureVersionRaw = [regex]::Match($versionLine, '^Version="([^"]+)"').Groups[1].Value
$fixtureVersionParts = $fixtureVersionRaw.Split('.')
if ($fixtureVersionParts.Count -lt 4) {
  throw "Fixture version '$fixtureVersionRaw' is not in major.minor.patch.build format."
}

$fixtureVersion = [ordered]@{
  major = [int]$fixtureVersionParts[0]
  minor = [int]$fixtureVersionParts[1]
  patch = [int]$fixtureVersionParts[2]
  build = [int]$fixtureVersionParts[3]
  raw   = $fixtureVersionRaw
}

$packagesRoot = Join-Path $extractRoot 'Packages'
$nestedVip = Get-ChildItem -LiteralPath $packagesRoot -Filter '*.vip' -Recurse -ErrorAction Stop | Select-Object -First 1
if (-not $nestedVip) {
  throw "Unable to locate nested system VIP inside fixture '${resolvedFixture}'."
}

$nestedExtract = Join-Path $extractRoot '__system_extract'
if (Test-Path -LiteralPath $nestedExtract) {
  Remove-Item -LiteralPath $nestedExtract -Recurse -Force
}

Expand-Archive -Path $nestedVip.FullName -DestinationPath $nestedExtract -Force

$lvlibpSource = Join-Path $nestedExtract 'File Group 0\National Instruments\LabVIEW Icon Editor\install\temp'
if (-not (Test-Path -LiteralPath $lvlibpSource -PathType Container)) {
  throw "Unable to locate lvlibp directory inside system VIP at '$lvlibpSource'."
}

$artifacts = @()

function Register-Artifact {
  param(
    [string]$SourcePath,
    [string]$DestinationPath,
    [string]$Kind
  )

  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
  $info = Get-Item -LiteralPath $DestinationPath
  return [ordered]@{
    name      = $info.Name
    path      = $info.FullName
    sizeBytes = $info.Length
    kind      = $Kind
  }
}

$fixtureDest = Join-Path $ResultsRoot (Split-Path -Leaf $resolvedFixture)
$artifacts += Register-Artifact -SourcePath $resolvedFixture -DestinationPath $fixtureDest -Kind 'vip'

$systemVipName = Split-Path -Leaf $nestedVip.FullName
$systemDest = Join-Path $ResultsRoot $systemVipName
$artifacts += Register-Artifact -SourcePath $nestedVip.FullName -DestinationPath $systemDest -Kind 'vip'

Get-ChildItem -LiteralPath $lvlibpSource -Filter '*.lvlibp' | ForEach-Object {
  $dest = Join-Path $ResultsRoot $_.Name
  $artifacts += Register-Artifact -SourcePath $_.FullName -DestinationPath $dest -Kind 'lvlibp'
}

$expectedVersionValue = $ExpectedVersion
if ($expectedVersionValue -is [string] -and $expectedVersionValue) {
  try {
    $expectedVersionValue = $expectedVersionValue | ConvertFrom-Json -AsHashtable -Depth 6
  } catch {
    $expectedVersionValue = $null
  }
} elseif ($expectedVersionValue -is [pscustomobject]) {
  $expectedVersionValue = $expectedVersionValue | ConvertTo-Json | ConvertFrom-Json -AsHashtable -Depth 6
}

$packageSmokeScript = Join-Path $repoRoot 'tools' 'icon-editor' 'Test-IconEditorPackage.ps1'
$packageSmokeSummary = $null
if (Test-Path -LiteralPath $packageSmokeScript -PathType Leaf) {
  $fixtureCommit = 'fixture'
  if ($expectedVersionValue -and $expectedVersionValue.ContainsKey('commit') -and $expectedVersionValue['commit']) {
    $fixtureCommit = $expectedVersionValue['commit']
  }

  $fixtureVersionInfo = [ordered]@{
    major  = $fixtureVersion.major
    minor  = $fixtureVersion.minor
    patch  = $fixtureVersion.patch
    build  = $fixtureVersion.build
    commit = $fixtureCommit
  }

  $vipTargets = @($systemDest)
  $packageSmokeSummary = & $packageSmokeScript `
    -VipPath $vipTargets `
    -ResultsRoot $ResultsRoot `
    -VersionInfo $fixtureVersionInfo `
    -RequireVip
}

$expectedVersionOrdered = Convert-ToOrderedHashtable $expectedVersionValue
if ($expectedVersionOrdered) {
  $hasNumericParts =
    $expectedVersionOrdered.Contains('major') -and
    $expectedVersionOrdered.Contains('minor') -and
    $expectedVersionOrdered.Contains('patch') -and
    $expectedVersionOrdered.Contains('build')
  if ($hasNumericParts -and -not $expectedVersionOrdered.Contains('raw')) {
    $expectedVersionOrdered['raw'] = '{0}.{1}.{2}.{3}' -f `
      $expectedVersionOrdered['major'], `
      $expectedVersionOrdered['minor'], `
      $expectedVersionOrdered['patch'], `
      $expectedVersionOrdered['build']
  }
}

$manifest = [ordered]@{
  schema              = 'icon-editor/build@v1'
  generatedAt         = (Get-Date).ToString('o')
  resultsRoot         = $ResultsRoot
  packagingRequested  = $true
  dependenciesApplied = $false
  unitTestsRun        = $false
  simulation          = [ordered]@{
    enabled     = $true
    fixturePath = $resolvedFixture
  }
  version             = [ordered]@{
    fixture  = $fixtureVersion
  }
  artifacts           = @()
}

if ($expectedVersionOrdered) {
  $manifest.version.expected = $expectedVersionOrdered
}

foreach ($artifact in $artifacts) {
  $manifest.artifacts += $artifact
}

if ($packageSmokeSummary) {
  $manifest.packageSmoke = $packageSmokeSummary
}

$manifestPath = Join-Path $ResultsRoot 'manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

if (-not $KeepExtract.IsPresent) {
  if (Test-Path -LiteralPath $nestedExtract) {
    Remove-Item -LiteralPath $nestedExtract -Recurse -Force
  }
  if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
  }
}

return [pscustomobject]$manifest
