#Requires -Version 7.0

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
  [int[]]$BuildVersions,
  [int[]]$BuildBitness,
  [int]$PackageVersion,
  [int]$PackageBitness,
  [bool]$InstallDependencies = $true,
  [switch]$SkipPackaging,
  [switch]$RequirePackaging,
  [switch]$RunUnitTests,
  [string]$ResultsRoot,
  [ValidateSet('gcli','vipm','vipm-cli')]
  [string]$BuildToolchain = 'gcli',
  [string]$BuildProvider
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try { return (git -C $StartPath rev-parse --show-toplevel 2>$null).Trim() } catch { return $StartPath }
}

$repoRoot = Resolve-RepoRoot
Import-Module (Join-Path $repoRoot 'tools' 'VendorTools.psm1') -Force
Import-Module (Join-Path $repoRoot 'tools' 'icon-editor' 'IconEditorDevMode.psm1') -Force

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
$buildTargets = Get-LabVIEWOperationTargets -Operation 'iconEditorBuildPackedLibs' -RepoRoot $repoRoot
if (-not $buildTargets) {
  $buildTargets = @(
    [pscustomobject]@{ Version = 2021; Bitness = 32 },
    [pscustomobject]@{ Version = 2021; Bitness = 64 }
  )
} else {
  $buildTargets = @($buildTargets)
}

$overrideBuildVersions = @()
if ($PSBoundParameters.ContainsKey('BuildVersions') -and $BuildVersions) {
  $overrideBuildVersions = @($BuildVersions | ForEach-Object { [int]$_ })
}
$overrideBuildBitness = @()
if ($PSBoundParameters.ContainsKey('BuildBitness') -and $BuildBitness) {
  $overrideBuildBitness = @($BuildBitness | ForEach-Object { [int]$_ })
}
if ($overrideBuildVersions.Count -gt 0 -or $overrideBuildBitness.Count -gt 0) {
  if ($overrideBuildVersions.Count -eq 0) {
    $overrideBuildVersions = @($buildTargets | Select-Object -ExpandProperty Version -Unique)
  }
  if ($overrideBuildBitness.Count -eq 0) {
    $overrideBuildBitness = @($buildTargets | Select-Object -ExpandProperty Bitness -Unique)
  }

  $targetMap = @{}
  foreach ($versionValue in $overrideBuildVersions) {
    foreach ($bitnessValue in $overrideBuildBitness) {
      $key = '{0}-{1}' -f $versionValue, $bitnessValue
      if (-not $targetMap.ContainsKey($key)) {
        $targetMap[$key] = [pscustomobject]@{
          Version = [int]$versionValue
          Bitness = [int]$bitnessValue
        }
      }
    }
  }
  $buildTargets = @(
    $targetMap.GetEnumerator() |
      Sort-Object Name |
      ForEach-Object { $_.Value }
  )
}

$packageTargets = Get-LabVIEWOperationTargets -Operation 'iconEditorPackageVip' -RepoRoot $repoRoot
if (-not $packageTargets) {
  $packageTargets = @(
    [pscustomobject]@{ Version = 2025; Bitness = 64 }
  )
} else {
  $packageTargets = @($packageTargets)
}
$packageTarget = @($packageTargets)[0]
if ($PSBoundParameters.ContainsKey('PackageVersion') -or $PSBoundParameters.ContainsKey('PackageBitness')) {
  $packageVersionOverride = if ($PSBoundParameters.ContainsKey('PackageVersion') -and $PackageVersion) { [int]$PackageVersion } else { [int]$packageTarget.Version }
  $packageBitnessOverride = if ($PSBoundParameters.ContainsKey('PackageBitness') -and $PackageBitness) { [int]$PackageBitness } else { [int]$packageTarget.Bitness }
  $packageTarget = [pscustomobject]@{
    Version = $packageVersionOverride
    Bitness = $packageBitnessOverride
  }
  $packageTargets = @($packageTarget)
}

$devModeVersions = @($buildTargets | Select-Object -ExpandProperty Version -Unique | Sort-Object)
$devModeBitness  = @($buildTargets | Select-Object -ExpandProperty Bitness -Unique | Sort-Object)
$devModeParams = @{
  RepoRoot = $repoRoot
  IconEditorRoot = $IconEditorRoot
  Operation = 'BuildPackage'
}
if ($devModeVersions.Count -gt 0) { $devModeParams.Versions = $devModeVersions }
if ($devModeBitness.Count -gt 0)  { $devModeParams.Bitness  = $devModeBitness }

if (-not $PSBoundParameters.ContainsKey('MinimumSupportedLVVersion') -or -not $MinimumSupportedLVVersion) {
  $MinimumSupportedLVVersion = [string]$buildTargets[0].Version
}

$requiredMap = @{}
foreach ($entry in (@($buildTargets) + @($packageTargets))) {
  if (-not $entry) { continue }
  $key = '{0}-{1}' -f $entry.Version, $entry.Bitness
  if (-not $requiredMap.ContainsKey($key)) {
    $requiredMap[$key] = $entry
  }
}

$missingLabVIEW = @()
foreach ($requirement in $requiredMap.GetEnumerator() | ForEach-Object { $_.Value }) {
  $requiredPath = Find-LabVIEWVersionExePath -Version ([int]$requirement.Version) -Bitness ([int]$requirement.Bitness)
  if (-not $requiredPath) {
    $missingLabVIEW += $requirement
  }
}
if ($missingLabVIEW.Count -gt 0) {
  $missingText = ($missingLabVIEW | ForEach-Object { "LabVIEW {0} ({1}-bit)" -f $_.Version, $_.Bitness }) -join ', '
  throw ("Required LabVIEW installations not found: {0}. Install the missing versions or set `versions.<version>.<bitness>.LabVIEWExePath` in configs/labview-paths.local.json." -f $missingText)
}
$packageVersion = [string]$packageTarget.Version
$packageBitness = [string]$packageTarget.Bitness
$devModeWasToggled = $false
$devModeActive = $false
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

  $unitTestScript     = Join-Path $actionsRoot 'run-unit-tests' 'RunUnitTests.ps1'
  $buildLvlibpScript  = Join-Path $actionsRoot 'build-lvlibp' 'Build_lvlibp.ps1'
  $closeLabviewScript = Join-Path $actionsRoot 'close-labview' 'Close_LabVIEW.ps1'
  $renameScript       = Join-Path $actionsRoot 'rename-file' 'Rename-file.ps1'
  $modifyVipbScript   = Join-Path $actionsRoot 'modify-vipb-display-info' 'ModifyVIPBDisplayInfo.ps1'
  $buildVipScript     = Join-Path $actionsRoot 'build-vi-package' 'build_vip.ps1'
  $packageSmokeScript = Join-Path $repoRoot 'tools' 'icon-editor' 'Test-IconEditorPackage.ps1'

  foreach ($required in @($buildLvlibpScript, $closeLabviewScript, $renameScript, $modifyVipbScript, $buildVipScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "Expected script '$required' was not found."
    }
  }

  function Invoke-IconEditorAction {
    param(
      [string]$ScriptPath,
      [string[]]$Arguments
    )

    Invoke-IconEditorDevModeScript -ScriptPath $ScriptPath -ArgumentList $Arguments -RepoRoot $repoRoot -IconEditorRoot $IconEditorRoot
  }

  if ($SkipPackaging.IsPresent -and $RequirePackaging.IsPresent) {
    throw 'Specify either -SkipPackaging or -RequirePackaging, not both.'
  }

  $packagingRequested = -not $SkipPackaging.IsPresent
  if ($RequirePackaging.IsPresent) {
    $packagingRequested = $true
  }

  $buildStart = Get-Date

  $previousDevState = Get-IconEditorDevModeState -RepoRoot $repoRoot
  $devModeWasToggled = $false
  $devModeActive = $false
  if ($InstallDependencies -and (-not $previousDevState.Active)) {
    Write-Host 'Enabling icon editor development mode...' -ForegroundColor Cyan
    Enable-IconEditorDevelopmentMode @devModeParams | Out-Null
    $devModeWasToggled = $true
    $devModeActive = $true
  } elseif ($previousDevState.Active) {
    $devModeActive = $true
  }

  Assert-IconEditorDevelopmentToken `
    -RepoRoot $repoRoot `
    -IconEditorRoot $IconEditorRoot `
    -Versions $devModeVersions `
    -Bitness $devModeBitness `
    -Operation 'BuildPackage' | Out-Null

  $pluginsPath = Join-Path $IconEditorRoot 'resource' 'plugins'
  if (Test-Path -LiteralPath $pluginsPath -PathType Container) {
    Get-ChildItem -LiteralPath $pluginsPath -Filter '*.lvlibp' -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $_) { return }
      $itemPath = $null
      if ($_.PSObject -and $null -ne ($_.PSObject.Properties['FullName'])) {
        $itemPath = $_.FullName
      } elseif ($_ -is [string]) {
        $itemPath = $_
      }
      if (-not $itemPath) { return }
      try {
        Remove-Item -LiteralPath $itemPath -Force -ErrorAction SilentlyContinue
      } catch {
        Write-Warning ("Failed to remove existing lvlibp artifact '{0}': {1}" -f $itemPath, $_.Exception.Message)
      }
    }
  }

  $lvLibPath = Join-Path $pluginsPath 'lv_icon.lvlibp'

  Write-Host 'Building icon editor packed libraries...' -ForegroundColor Cyan

  foreach ($target in $buildTargets) {
    $targetVersion = [string]$target.Version
    $targetBitness = [string]$target.Bitness
    $suffix = switch ([int]$target.Bitness) {
      32 { 'x86' }
      64 { 'x64' }
      default { "x$($target.Bitness)" }
    }
    $targetName = "lv_icon_{0}.lvlibp" -f $suffix

    Invoke-IconEditorAction `
      -ScriptPath $buildLvlibpScript `
      -Arguments @(
        '-MinimumSupportedLVVersion', $targetVersion,
        '-SupportedBitness', $targetBitness,
        '-RelativePath', $IconEditorRoot,
        '-Major', "$Major",
        '-Minor', "$Minor",
        '-Patch', "$Patch",
        '-Build', "$Build",
        '-Commit', $Commit
      )

    Invoke-IconEditorAction `
      -ScriptPath $closeLabviewScript `
      -Arguments @(
        '-MinimumSupportedLVVersion', $targetVersion,
        '-SupportedBitness', $targetBitness
      )

    Invoke-IconEditorAction `
      -ScriptPath $renameScript `
      -Arguments @(
        '-CurrentFilename', $lvLibPath,
        '-NewFilename', $targetName
      )
  }

  $displayInfo = [ordered]@{
    'Package Version' = [ordered]@{
      major = $Major
      minor = $Minor
      patch = $Patch
      build = $Build
    }
    'Product Name'                   = ''
    'Company Name'                   = $CompanyName
    'Author Name (Person or Company)' = $AuthorName
    'Product Homepage (URL)'         = ''
    'Legal Copyright'                = ''
    'License Agreement Name'         = ''
    'Product Description Summary'    = ''
    'Product Description'            = ''
    'Release Notes - Change Log'     = ''
  }

  $displayInfoJson = $displayInfo | ConvertTo-Json -Depth 3
  $vipArtifacts = @()
  $packageSmokeSummary = $null

  if ($packagingRequested) {
    Write-Host 'Packaging icon editor VIP...' -ForegroundColor Cyan

    $vipbRelativePath = 'Tooling\deployment\NI Icon editor.vipb'
    $releaseNotesPath = Join-Path $IconEditorRoot 'Tooling\deployment\release_notes.md'

    Invoke-IconEditorAction `
      -ScriptPath $modifyVipbScript `
      -Arguments @(
        '-SupportedBitness', $packageBitness,
        '-RelativePath', $IconEditorRoot,
        '-VIPBPath', $vipbRelativePath,
        '-MinimumSupportedLVVersion', $packageVersion,
        '-LabVIEWMinorRevision', "$LabVIEWMinorRevision",
        '-Major', "$Major",
        '-Minor', "$Minor",
        '-Patch', "$Patch",
        '-Build', "$Build",
        '-Commit', $Commit,
        '-ReleaseNotesFile', $releaseNotesPath,
        '-DisplayInformationJSON', $displayInfoJson
    )

    $vipArguments = @(
      '-SupportedBitness', $packageBitness,
      '-MinimumSupportedLVVersion', $packageVersion,
      '-LabVIEWMinorRevision', "$LabVIEWMinorRevision",
      '-Major', "$Major",
      '-Minor', "$Minor",
      '-Patch', "$Patch",
      '-Build', "$Build",
      '-Commit', $Commit,
      '-ReleaseNotesFile', $releaseNotesPath,
      '-DisplayInformationJSON', $displayInfoJson,
      '-BuildToolchain', $BuildToolchain
    )
    if ($BuildProvider) {
      $vipArguments += @('-BuildProvider', $BuildProvider)
    }
    Invoke-IconEditorAction `
      -ScriptPath $buildVipScript `
      -Arguments $vipArguments

    Invoke-IconEditorAction `
      -ScriptPath $closeLabviewScript `
      -Arguments @(
        '-MinimumSupportedLVVersion', $packageVersion,
        '-SupportedBitness', $packageBitness
      )

    $vipCandidates = Get-ChildItem -Path $IconEditorRoot -Filter '*.vip' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $buildStart }
    foreach ($vip in $vipCandidates) {
      $destName = $vip.Name
      $destPath = Join-Path $ResultsRoot $destName
      Copy-Item -LiteralPath $vip.FullName -Destination $destPath -Force
      $vipArtifacts += @{ Source = $vip.FullName; Name = $destName; Kind = 'vip' }
    }
  } elseif ($RequirePackaging.IsPresent) {
    throw 'Packaging was required but could not be executed.'
  } else {
    Write-Host 'Packaging skipped by request.' -ForegroundColor Yellow
  }

  if (Test-Path -LiteralPath $packageSmokeScript -PathType Leaf) {
    $vipDestinations = @()
    foreach ($entry in $vipArtifacts) {
      $vipDestinations += (Join-Path $ResultsRoot $entry.Name)
    }

    try {
      $packageSmokeSummary = & $packageSmokeScript `
        -VipPath $vipDestinations `
        -ResultsRoot $ResultsRoot `
        -VersionInfo @{
          major  = $Major
          minor  = $Minor
          patch  = $Patch
          build  = $Build
          commit = $Commit
        } `
        -RequireVip:$packagingRequested
    } catch {
      if ($RequirePackaging.IsPresent -or $packagingRequested) {
        throw
      }

      Write-Warning "Package smoke test failed: $($_.Exception.Message)"
    }
  }

  $artifactMap = @(
    @{ Source = Join-Path $IconEditorRoot 'resource\plugins\lv_icon_x86.lvlibp'; Name = 'lv_icon_x86.lvlibp'; Kind = 'lvlibp' },
    @{ Source = Join-Path $IconEditorRoot 'resource\plugins\lv_icon_x64.lvlibp'; Name = 'lv_icon_x64.lvlibp'; Kind = 'lvlibp' }
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
      $unitTestProject = Join-Path $IconEditorRoot 'lv_icon_editor.lvproj'
      & $unitTestScript `
        -MinimumSupportedLVVersion $MinimumSupportedLVVersion `
        -SupportedBitness '64' `
        -ProjectPath $unitTestProject
    } finally {
      Pop-Location
    }

    $reportPath = Join-Path (Split-Path -Parent $unitTestScript) 'UnitTestReport.xml'
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
      Copy-Item -LiteralPath $reportPath -Destination (Join-Path $ResultsRoot 'UnitTestReport.xml') -Force
    }
  }

  if ($devModeActive -and $devModeWasToggled) {
    Write-Host 'Disabling icon editor development mode...' -ForegroundColor Cyan
    try {
      Disable-IconEditorDevelopmentMode @devModeParams | Out-Null
      $devModeActive = $false
    } catch {
      Write-Warning "Failed to disable icon editor development mode: $($_.Exception.Message)"
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
    dependenciesApplied = [bool]$devModeWasToggled
    unitTestsRun        = [bool]$RunUnitTests
    packagingRequested  = [bool]$packagingRequested
    artifacts = @()
  }

  $manifest.packaging = [ordered]@{
    requestedToolchain = $BuildToolchain
  }
  if ($BuildProvider) {
    $manifest.packaging.requestedProvider = $BuildProvider
  }

  if ($packageSmokeSummary) {
    $manifest.packageSmoke = $packageSmokeSummary
  }

  $devModeState = Get-IconEditorDevModeState -RepoRoot $repoRoot
  $manifest.developmentMode = [ordered]@{
    active    = $devModeState.Active
    updatedAt = $devModeState.UpdatedAt
    source    = $devModeState.Source
    toggled   = [bool]$devModeWasToggled
  }

  foreach ($artifact in $artifactMap) {
    $dest = Join-Path $ResultsRoot $artifact.Name
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
      $info = Get-Item -LiteralPath $dest
      $manifest.artifacts += [ordered]@{
        name = $artifact.Name
        path = $info.FullName
        sizeBytes = $info.Length
        kind = $artifact.Kind
      }
    }
  }

  foreach ($entry in $vipArtifacts) {
    $dest = Join-Path $ResultsRoot $entry.Name
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
      $info = Get-Item -LiteralPath $dest
      $manifest.artifacts += [ordered]@{
        name = $entry.Name
        path = $info.FullName
        sizeBytes = $info.Length
        kind = $entry.Kind
      }
    }
  }

  $manifestPath = Join-Path $ResultsRoot 'manifest.json'
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

  Write-Host "Icon Editor build completed. Artifacts captured in $ResultsRoot"
}
finally {
  if ($devModeWasToggled -and $devModeActive) {
    try {
      Write-Host 'Disabling icon editor development mode...' -ForegroundColor Cyan
      Disable-IconEditorDevelopmentMode @devModeParams | Out-Null
    } catch {
      Write-Warning "Failed to disable icon editor development mode: $($_.Exception.Message)"
    }
  }
  $env:Path = $previousPath
}
