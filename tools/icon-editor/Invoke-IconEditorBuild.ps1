#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
  [string]$IconEditorRoot,
  [int]$Major = 0,
  [int]$Minor = 0,
  [int]$Patch = 0,
  [int]$Build = 0,
  [string]$Commit,
  [string]$CompanyName = 'LabVIEW Community CI/CD',
  [string]$AuthorName = 'LabVIEW Community CI/CD',
  [string]$MinimumSupportedLVVersion = '2021',
  [int]$LabVIEWMinorRevision = 3,
  [switch]$InstallDependencies,
  [switch]$RunUnitTests,
  [string]$ResultsRoot
)

function Resolve-RepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try { return (git -C $StartPath rev-parse --show-toplevel 2>$null).Trim() } catch { return $StartPath }
}

$repoRoot = Resolve-RepoRoot
Import-Module (Join-Path $repoRoot 'tools' 'VendorTools.psm1') -Force

if (-not $IconEditorRoot) {
  $IconEditorRoot = Join-Path $repoRoot 'vendor' 'icon-editor'
}

if (-not (Test-Path -LiteralPath $IconEditorRoot -PathType Container)) {
  throw "Icon editor root not found at '$IconEditorRoot'. Vendor the labview-icon-editor repository first."
}

if (-not $ResultsRoot) {
  $ResultsRoot = Join-Path $repoRoot 'tests' 'results' '_agent' 'icon-editor'
}

$ResultsRoot = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $ResultsRoot -Force)).Path

$gCliPath = Resolve-GCliPath
if (-not $gCliPath) {
  throw "Unable to locate g-cli.exe. Update configs/labview-paths.local.json or set GCLI_EXE_PATH so the automation can find g-cli."
}

$gCliDirectory = Split-Path -Parent $gCliPath
$previousPath = $env:Path
try {
  if ($previousPath -notlike "$gCliDirectory*") {
    $env:Path = "$gCliDirectory;$previousPath"
  }

  if (-not $Commit) {
    try {
      $Commit = (git -C $repoRoot rev-parse --short HEAD).Trim()
    } catch {
      $Commit = 'vendored'
    }
  }

  $actionsRoot = Join-Path $IconEditorRoot '.github' 'actions'

  $applyVipcScript = Join-Path $actionsRoot 'apply-vipc' 'ApplyVIPC.ps1'
  $buildScript     = Join-Path $actionsRoot 'build' 'Build.ps1'
  $unitTestScript  = Join-Path $actionsRoot 'run-unit-tests' 'RunUnitTests.ps1'

  foreach ($required in @($buildScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "Expected script '$required' was not found."
    }
  }

  if ($InstallDependencies) {
    if (-not (Test-Path -LiteralPath $applyVipcScript -PathType Leaf)) {
      throw "Requested dependency install but '$applyVipcScript' is missing."
    }

    foreach ($bitness in @('32','64')) {
      & $applyVipcScript `
        -MinimumSupportedLVVersion $MinimumSupportedLVVersion `
        -SupportedBitness $bitness `
        -RelativePath $IconEditorRoot `
        -VIPCPath '.github\actions\apply-vipc\runner_dependencies.vipc' `
        -VIP_LVVersion $MinimumSupportedLVVersion `
        -Verbose
    }
  }

  & $buildScript `
    -RelativePath $IconEditorRoot `
    -Major $Major `
    -Minor $Minor `
    -Patch $Patch `
    -Build $Build `
    -Commit $Commit `
    -LabVIEWMinorRevision $LabVIEWMinorRevision `
    -CompanyName $CompanyName `
    -AuthorName $AuthorName `
    -Verbose

  $artifactMap = @(
    @{ Source = Join-Path $IconEditorRoot 'resource\plugins\lv_icon_x86.lvlibp'; Name = 'lv_icon_x86.lvlibp' },
    @{ Source = Join-Path $IconEditorRoot 'resource\plugins\lv_icon_x64.lvlibp'; Name = 'lv_icon_x64.lvlibp' }
  )

  foreach ($artifact in $artifactMap) {
    if (Test-Path -LiteralPath $artifact.Source -PathType Leaf) {
      Copy-Item -LiteralPath $artifact.Source -Destination (Join-Path $ResultsRoot $artifact.Name) -Force
    }
  }

  if ($RunUnitTests) {
    if (-not (Test-Path -LiteralPath $unitTestScript -PathType Leaf)) {
      throw "Unit test script '$unitTestScript' not found."
    }

    Push-Location (Split-Path -Parent $unitTestScript)
    try {
      & $unitTestScript -MinimumSupportedLVVersion $MinimumSupportedLVVersion -SupportedBitness '64'
    } finally {
      Pop-Location
    }

    $reportPath = Join-Path (Split-Path -Parent $unitTestScript) 'UnitTestReport.xml'
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
      Copy-Item -LiteralPath $reportPath -Destination (Join-Path $ResultsRoot 'UnitTestReport.xml') -Force
    }
  }

  $manifest = [ordered]@{
    schema        = 'icon-editor/build@v1'
    generatedAt   = (Get-Date).ToString('o')
    iconEditorRoot = $IconEditorRoot
    resultsRoot   = $ResultsRoot
    version       = @{
      major = $Major
      minor = $Minor
      patch = $Patch
      build = $Build
      commit = $Commit
    }
    dependenciesApplied = [bool]$InstallDependencies
    unitTestsRun        = [bool]$RunUnitTests
    artifacts = @()
  }

  foreach ($artifact in $artifactMap) {
    $dest = Join-Path $ResultsRoot $artifact.Name
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
      $info = Get-Item -LiteralPath $dest
      $manifest.artifacts += [ordered]@{
        name = $artifact.Name
        path = $info.FullName
        sizeBytes = $info.Length
      }
    }
  }

  $manifestPath = Join-Path $ResultsRoot 'manifest.json'
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

  Write-Host "Icon Editor build completed. Artifacts captured in $ResultsRoot"
}
finally {
  $env:Path = $previousPath
}
