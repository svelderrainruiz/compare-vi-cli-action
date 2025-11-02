#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-IconEditorRepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try {
    $root = git -C $StartPath rev-parse --show-toplevel 2>$null
    if ($root) {
      return (Resolve-Path -LiteralPath $root.Trim()).Path
    }
  } catch {
    # fall back to supplied path
  }
  return (Resolve-Path -LiteralPath $StartPath).Path
}

function Resolve-IconEditorRoot {
  param([string]$RepoRoot)
  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  }
  $root = Join-Path $RepoRoot 'vendor' 'icon-editor'
  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Icon editor root not found at '$root'. Vendor the labview-icon-editor repository first."
  }
  return (Resolve-Path -LiteralPath $root).Path
}

function Get-IconEditorDevModeStatePath {
  param([string]$RepoRoot)
  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  }
  return Join-Path $RepoRoot 'tests' 'results' '_agent' 'icon-editor' 'dev-mode-state.json'
}

function Get-IconEditorDevModeState {
  param([string]$RepoRoot)
  $statePath = Get-IconEditorDevModeStatePath -RepoRoot $RepoRoot
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    return [pscustomobject]@{
      Active    = $null
      UpdatedAt = $null
      Source    = $null
      Path      = $statePath
    }
  }

  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Failed to parse icon editor dev-mode state file at '$statePath': $($_.Exception.Message)"
  }

  return [pscustomobject]@{
    Active    = $state.active
    UpdatedAt = $state.updatedAt
    Source    = $state.source
    Path      = $statePath
  }
}

function Set-IconEditorDevModeState {
  param(
    [Parameter(Mandatory)][bool]$Active,
    [string]$RepoRoot,
    [string]$Source
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  $statePath = Get-IconEditorDevModeStatePath -RepoRoot $RepoRoot
  $stateDir = Split-Path -Parent $statePath
  if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  }

  $payload = [ordered]@{
    schema    = 'icon-editor/dev-mode-state@v1'
    updatedAt = (Get-Date).ToString('o')
    active    = [bool]$Active
    source    = $Source
  }

  $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
  return Get-IconEditorDevModeState -RepoRoot $RepoRoot
}

function Invoke-IconEditorDevModeScript {
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ArgumentList,
    [string]$RepoRoot,
    [string]$IconEditorRoot
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  if (-not $IconEditorRoot) {
    $IconEditorRoot = Resolve-IconEditorRoot -RepoRoot $RepoRoot
  } else {
    $IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path
  }

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Icon editor dev-mode script not found at '$ScriptPath'."
  }

  Import-Module (Join-Path $RepoRoot 'tools' 'VendorTools.psm1') -Force
  $gCliPath = Resolve-GCliPath
  if (-not $gCliPath) {
    throw "Unable to locate g-cli.exe. Update configs/labview-paths.local.json or set GCLI_EXE_PATH so the dev-mode helper can find g-cli."
  }

  $scriptDirectory = Split-Path -Parent $ScriptPath
  $previousLocation = Get-Location
  $previousPath = $env:Path
  $gCliDirectory = Split-Path -Parent $gCliPath

  $pwshCmd = Get-Command pwsh -ErrorAction Stop
  $args = if ($ArgumentList -and $ArgumentList.Count -gt 0) { $ArgumentList } else { @('-RelativePath', $IconEditorRoot) }

  Set-Location -LiteralPath $scriptDirectory
  try {
    if ($previousPath -notlike "$gCliDirectory*") {
      $env:Path = "$gCliDirectory;$previousPath"
    }

    & $pwshCmd.Source -NoLogo -NoProfile -File $ScriptPath @args
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
      throw "Dev-mode script '$ScriptPath' exited with code $exitCode."
    }
  }
  finally {
    Set-Location -LiteralPath $previousLocation.Path
    $env:Path = $previousPath
  }
}

function Enable-IconEditorDevelopmentMode {
  param(
    [string]$RepoRoot,
    [string]$IconEditorRoot
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  if (-not $IconEditorRoot) {
    $IconEditorRoot = Resolve-IconEditorRoot -RepoRoot $RepoRoot
  } else {
    $IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path
  }

  $actionsRoot = Join-Path $IconEditorRoot '.github' 'actions'
  $addTokenScript = Join-Path $actionsRoot 'add-token-to-labview' 'AddTokenToLabVIEW.ps1'
  $prepareScript  = Join-Path $actionsRoot 'prepare-labview-source' 'Prepare_LabVIEW_source.ps1'
  $closeScript    = Join-Path $actionsRoot 'close-labview' 'Close_LabVIEW.ps1'

  foreach ($required in @($addTokenScript, $prepareScript, $closeScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "Icon editor dev-mode helper '$required' was not found."
    }
  }

  $pluginsPath = Join-Path $IconEditorRoot 'resource' 'plugins'
  if (Test-Path -LiteralPath $pluginsPath -PathType Container) {
    Get-ChildItem -LiteralPath $pluginsPath -Filter '*.lvlibp' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  }

  foreach ($bitness in @('32','64')) {
    Invoke-IconEditorDevModeScript `
      -ScriptPath $addTokenScript `
      -ArgumentList @(
        '-MinimumSupportedLVVersion','2021',
        '-SupportedBitness',        $bitness,
        '-RelativePath',            $IconEditorRoot
      ) `
      -RepoRoot $RepoRoot `
      -IconEditorRoot $IconEditorRoot

    Invoke-IconEditorDevModeScript `
      -ScriptPath $prepareScript `
      -ArgumentList @(
        '-MinimumSupportedLVVersion','2021',
        '-SupportedBitness',        $bitness,
        '-RelativePath',            $IconEditorRoot,
        '-LabVIEW_Project',         'lv_icon_editor',
        '-Build_Spec',              'Editor Packed Library'
      ) `
      -RepoRoot $RepoRoot `
      -IconEditorRoot $IconEditorRoot

    Invoke-IconEditorDevModeScript `
      -ScriptPath $closeScript `
      -ArgumentList @(
        '-MinimumSupportedLVVersion','2021',
        '-SupportedBitness',        $bitness
      ) `
      -RepoRoot $RepoRoot `
      -IconEditorRoot $IconEditorRoot
  }

  return Set-IconEditorDevModeState -RepoRoot $RepoRoot -Active $true -Source 'Enable-IconEditorDevelopmentMode'
}

function Disable-IconEditorDevelopmentMode {
  param(
    [string]$RepoRoot,
    [string]$IconEditorRoot
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  if (-not $IconEditorRoot) {
    $IconEditorRoot = Resolve-IconEditorRoot -RepoRoot $RepoRoot
  } else {
    $IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path
  }

  $actionsRoot = Join-Path $IconEditorRoot '.github' 'actions'
  $restoreScript = Join-Path $actionsRoot 'restore-setup-lv-source' 'RestoreSetupLVSource.ps1'
  $closeScript   = Join-Path $actionsRoot 'close-labview' 'Close_LabVIEW.ps1'

  foreach ($required in @($restoreScript, $closeScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
      throw "Icon editor dev-mode helper '$required' was not found."
    }
  }

  foreach ($bitness in @('32','64')) {
    Invoke-IconEditorDevModeScript `
      -ScriptPath $restoreScript `
      -ArgumentList @(
        '-MinimumSupportedLVVersion','2021',
        '-SupportedBitness',        $bitness,
        '-RelativePath',            $IconEditorRoot,
        '-LabVIEW_Project',         'lv_icon_editor',
        '-Build_Spec',              'Editor Packed Library'
      ) `
      -RepoRoot $RepoRoot `
      -IconEditorRoot $IconEditorRoot

    Invoke-IconEditorDevModeScript `
      -ScriptPath $closeScript `
      -ArgumentList @(
        '-MinimumSupportedLVVersion','2021',
        '-SupportedBitness',        $bitness
      ) `
      -RepoRoot $RepoRoot `
      -IconEditorRoot $IconEditorRoot
  }

  return Set-IconEditorDevModeState -RepoRoot $RepoRoot -Active $false -Source 'Disable-IconEditorDevelopmentMode'
}

function Get-IconEditorDevModeLabVIEWTargets {
  param(
    [string]$RepoRoot,
    [string]$IconEditorRoot,
    [int[]]$Versions = @(2021),
    [int[]]$Bitness = @(32, 64)
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  if (-not $IconEditorRoot) {
    $IconEditorRoot = Resolve-IconEditorRoot -RepoRoot $RepoRoot
  } else {
    $IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path
  }

  Import-Module (Join-Path $RepoRoot 'tools' 'VendorTools.psm1') -Force

  $targets = New-Object System.Collections.Generic.List[object]
  foreach ($version in $Versions) {
    foreach ($bit in $Bitness) {
      $exePath = Find-LabVIEWVersionExePath -Version $version -Bitness $bit
      $iniPath = $null
      $present = $false
      if ($exePath) {
        $present = $true
        $iniPath = Get-LabVIEWIniPath -LabVIEWExePath $exePath
      }
      $targets.Add([pscustomobject]@{
        Version = $version
        Bitness = $bit
        LabVIEWExePath = $exePath
        LabVIEWIniPath = $iniPath
        Present = [bool]$present
        IconEditorRoot = $IconEditorRoot
      }) | Out-Null
    }
  }

  return $targets.ToArray()
}

function Test-IconEditorDevelopmentMode {
  param(
    [string]$RepoRoot,
    [string]$IconEditorRoot
  )

  if (-not $RepoRoot) {
    $RepoRoot = Resolve-IconEditorRepoRoot
  } else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  if (-not $IconEditorRoot) {
    $IconEditorRoot = Resolve-IconEditorRoot -RepoRoot $RepoRoot
  } else {
    $IconEditorRoot = (Resolve-Path -LiteralPath $IconEditorRoot).Path
  }

  $iconEditorRootLower = $IconEditorRoot.ToLowerInvariant().TrimEnd('\')
  $targets = Get-IconEditorDevModeLabVIEWTargets -RepoRoot $RepoRoot -IconEditorRoot $IconEditorRoot
  $results = New-Object System.Collections.Generic.List[object]

  foreach ($target in $targets) {
    $tokenValue = $null
    $containsIconEditor = $false
    if ($target.Present -and $target.LabVIEWIniPath -and (Test-Path -LiteralPath $target.LabVIEWIniPath -PathType Leaf)) {
      try {
        $tokenValue = Get-LabVIEWIniValue -Key 'LocalHost.LibraryPaths' -LabVIEWExePath $target.LabVIEWExePath -LabVIEWIniPath $target.LabVIEWIniPath
      } catch {
        $tokenValue = $null
      }
      if ($tokenValue) {
        $normalizedValue = ($tokenValue -replace '"', '').Split(';') | ForEach-Object {
          $_.Trim().TrimEnd('\').ToLowerInvariant()
        }
        foreach ($entry in $normalizedValue) {
          if ($entry -eq '') { continue }
          if ($entry -eq $iconEditorRootLower -or $entry.StartsWith($iconEditorRootLower)) {
            $containsIconEditor = $true
            break
          }
        }
      }
    }

    $results.Add([pscustomobject]@{
      Version = $target.Version
      Bitness = $target.Bitness
      LabVIEWExePath = $target.LabVIEWExePath
      LabVIEWIniPath = $target.LabVIEWIniPath
      Present = $target.Present
      TokenValue = $tokenValue
      ContainsIconEditorPath = $containsIconEditor
    }) | Out-Null
  }

  $presentEntries = $results | Where-Object { $_.Present }
  $active = $null
  if ($presentEntries.Count -gt 0) {
    $active = $presentEntries | ForEach-Object { $_.ContainsIconEditorPath } | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
    $active = ($active -eq $presentEntries.Count)
  }

  return [pscustomobject]@{
    RepoRoot = $RepoRoot
    IconEditorRoot = $IconEditorRoot
    Active = $active
    Entries = $results
  }
}

Export-ModuleMember -Function `
  Resolve-IconEditorRepoRoot, `
  Resolve-IconEditorRoot, `
  Get-IconEditorDevModeStatePath, `
  Get-IconEditorDevModeState, `
  Set-IconEditorDevModeState, `
  Invoke-IconEditorDevModeScript, `
  Enable-IconEditorDevelopmentMode, `
  Disable-IconEditorDevelopmentMode, `
  Get-IconEditorDevModeLabVIEWTargets, `
  Test-IconEditorDevelopmentMode
