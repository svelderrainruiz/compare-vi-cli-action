#Requires -Version 7.0

param(
  [string]$RemoteName = 'icon-editor',
  [string]$RepoSlug,
  [string]$Branch = 'develop',
  [string]$WorkspaceRoot,
  [string]$StageName,
  [string]$SourcePath,
  [string]$FixturePath,
  [string]$BaselineFixture,
  [string]$BaselineManifest,
  [string]$ResourceOverlayRoot,
  [string]$InvokeValidateScript,
  [switch]$SkipValidate,
  [switch]$SkipLVCompare,
  [switch]$DryRun,
  [switch]$SkipBootstrapForValidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

function Resolve-RepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try {
    return (git -C $StartPath rev-parse --show-toplevel 2>$null).Trim()
  } catch {
    return $StartPath
  }
}

function Get-DirectoryPath {
  param([string]$Path)
  $resolved = Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $Path)
  return $resolved.Path
}

function Resolve-RelativePath {
  param(
    [string]$BasePath,
    [string]$InputPath
  )
  if (-not $InputPath) {
    return $null
  }
  if ([System.IO.Path]::IsPathRooted($InputPath)) {
    return (Resolve-Path -LiteralPath $InputPath).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $BasePath $InputPath)).Path
}

function Resolve-ResourceRoot {
  param([string]$MirrorPath)
  $candidates = @(
    (Join-Path $MirrorPath 'resource')
    (Join-Path $MirrorPath 'Resource')
    $MirrorPath
  )
  foreach ($candidate in $candidates) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      continue
    }
    $pluginsChild = Join-Path $candidate 'plugins'
    if (Test-Path -LiteralPath $pluginsChild -PathType Container) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "Unable to locate a resource overlay root under '$MirrorPath'. Expected to find a directory containing 'plugins'."
}

$repoRoot = Resolve-RepoRoot
$syncScript = Join-Path $repoRoot 'tools/icon-editor/Sync-IconEditorFork.ps1'
$updateReportScript = Join-Path $repoRoot 'tools/icon-editor/Update-IconEditorFixtureReport.ps1'

if (-not (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
  throw "Sync helper not found at '$syncScript'."
}
if (-not (Test-Path -LiteralPath $updateReportScript -PathType Leaf)) {
  throw "Update-IconEditorFixtureReport.ps1 not found at '$updateReportScript'."
}

if (-not $InvokeValidateScript) {
  $InvokeValidateScript = Join-Path $repoRoot 'tools/icon-editor/Invoke-ValidateLocal.ps1'
}
$invokeValidateResolved = Resolve-RelativePath -BasePath $repoRoot -InputPath $InvokeValidateScript
if (-not (Test-Path -LiteralPath $invokeValidateResolved -PathType Leaf)) {
  throw "Invoke-ValidateLocal helper not found at '$invokeValidateResolved'."
}

if (-not $WorkspaceRoot) {
  $WorkspaceRoot = Join-Path $repoRoot 'tests/results/_agent/icon-editor/snapshots'
}
$workspaceResolved = Get-DirectoryPath $WorkspaceRoot

if (-not $StageName) {
  $StageName = 'snapshot-' + (Get-Date -Format 'yyyyMMddTHHmmss')
}
$stageRoot = Get-DirectoryPath (Join-Path $workspaceResolved $StageName)

$mirrorPath = $null
$resolvesExternalSource = $false
if ($SourcePath) {
  $mirrorPath = Resolve-RelativePath -BasePath $repoRoot -InputPath $SourcePath
  if (-not (Test-Path -LiteralPath $mirrorPath -PathType Container)) {
    throw "Source path '$mirrorPath' not found."
  }
  $resolvesExternalSource = $true
  Write-Information ("==> Reusing existing source at {0}" -f $mirrorPath)
} else {
  $mirrorDst = Get-DirectoryPath (Join-Path $stageRoot 'source')
  Write-Information ("==> Syncing fork to {0}" -f $mirrorDst)
  $syncArgs = @{
    RemoteName  = $RemoteName
    RepoSlug    = $RepoSlug
    Branch      = $Branch
    WorkingPath = $mirrorDst
  }
  $syncResult = & $syncScript @syncArgs
  if ($syncResult -isnot [pscustomobject]) {
    throw "Sync helper returned unexpected output."
  }
  $mirrorPath = if ($syncResult.PSObject.Properties['mirrorPath']) {
    $syncResult.mirrorPath
  } else {
    $mirrorDst
  }
  if (-not (Test-Path -LiteralPath $mirrorPath -PathType Container)) {
    throw "Synced mirror path '$mirrorPath' not found."
  }
}

$resourceOverlay = if ($ResourceOverlayRoot) {
  Resolve-RelativePath -BasePath $repoRoot -InputPath $ResourceOverlayRoot
} else {
  Resolve-ResourceRoot -MirrorPath $mirrorPath
}
if (-not (Test-Path -LiteralPath $resourceOverlay -PathType Container)) {
  throw "Resource overlay path not found at '$resourceOverlay'."
}
Write-Information ("==> Resource overlay resolved to {0}" -f $resourceOverlay)

$fixtureResolved = Resolve-RelativePath -BasePath $repoRoot -InputPath ($FixturePath ?? 'tests/fixtures/icon-editor/ni_icon_editor-1.4.1.948.vip')
$baselineFixtureResolved = Resolve-RelativePath -BasePath $repoRoot -InputPath ($BaselineFixture ?? 'tests/fixtures/icon-editor/ni_icon_editor-1.4.1.794.vip')
$baselineManifestResolved = Resolve-RelativePath -BasePath $repoRoot -InputPath ($BaselineManifest ?? 'tests/fixtures/icon-editor/fixture-manifest-1.4.1.794.json')

Write-Information "==> Fixture path          : $fixtureResolved"
Write-Information "==> Baseline fixture      : $baselineFixtureResolved"
Write-Information "==> Baseline manifest     : $baselineManifestResolved"
Write-Information "==> Snapshot workspace    : $stageRoot"

$reportRoot = Get-DirectoryPath (Join-Path $stageRoot 'report')
$headManifestPath = Join-Path $stageRoot 'head-manifest.json'

Write-Information '==> Generating snapshot report/manifest'
$reportSummary = & $updateReportScript `
  -FixturePath $fixtureResolved `
  -ManifestPath $headManifestPath `
  -ResultsRoot $reportRoot `
  -ResourceOverlayRoot $resourceOverlay `
  -SkipDocUpdate

$reportJsonPath = Join-Path $reportRoot 'fixture-report.json'
if (-not (Test-Path -LiteralPath $reportJsonPath -PathType Leaf)) {
  throw "Snapshot fixture-report.json not found at '$reportJsonPath'."
}
if (-not (Test-Path -LiteralPath $headManifestPath -PathType Leaf)) {
  throw "Head manifest not found at '$headManifestPath'."
}

$validateRoot = $null
if (-not $SkipValidate.IsPresent) {
  $validateRoot = Get-DirectoryPath (Join-Path $stageRoot 'validate')
  Write-Information ("==> Running Invoke-ValidateLocal (results -> {0})" -f $validateRoot)
  $validateParams = @{
    BaselineFixture     = $baselineFixtureResolved
    BaselineManifest    = $baselineManifestResolved
    ResourceOverlayRoot = $resourceOverlay
    ResultsRoot         = $validateRoot
  }
  if ($SkipLVCompare.IsPresent -or $DryRun.IsPresent) {
    $validateParams['SkipLVCompare'] = $true
  }
  if ($DryRun.IsPresent) {
    $validateParams['DryRun'] = $true
  }
  if ($SkipBootstrapForValidate.IsPresent) {
    $validateParams['SkipBootstrap'] = $true
  }
  & $invokeValidateResolved @validateParams | Out-Null
} else {
  Write-Information '==> SkipValidate requested; Invoke-ValidateLocal was not executed'
}

Write-Information '==> Snapshot staging complete'
Write-Information ("    Stage root        : {0}" -f $stageRoot)
Write-Information ("    Source (mirror)   : {0}" -f $mirrorPath)
Write-Information ("    Resource overlay  : {0}" -f $resourceOverlay)
Write-Information ("    Head manifest     : {0}" -f $headManifestPath)
Write-Information ("    Head report JSON  : {0}" -f $reportJsonPath)
if ($validateRoot) {
  Write-Information ("    Validate results  : {0}" -f $validateRoot)
}

return [pscustomobject]@{
  stageRoot        = $stageRoot
  mirrorPath       = $mirrorPath
  resourceOverlay  = $resourceOverlay
  fixturePath      = $fixtureResolved
  headManifestPath = $headManifestPath
  headReportPath   = $reportJsonPath
  validateRoot     = $validateRoot
  externalSource   = $resolvesExternalSource
}
