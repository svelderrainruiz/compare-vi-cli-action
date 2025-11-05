#Requires -Version 7.0

<#
.SYNOPSIS
    Replays the GitHub Actions "Build Packed Library" job locally.

.DESCRIPTION
    Downloads (or consumes an existing) job log, extracts the version, commit,
    LabVIEW version, and bitness inputs, then re-invokes the build/close/rename
    helpers to produce the lv_icon_{suffix}.lvlibp artifact locally.

.PARAMETER RunId
    Workflow run identifier to fetch. When supplied the script uses `gh` to
    download the matching job log.

.PARAMETER LogPath
    Path to a pre-downloaded job log. Required when RunId is omitted.

.PARAMETER JobName
    Name of the job to replay. Defaults to "Build {Bitness}-bit Packed Library"
    when Bitness is provided, otherwise "Build 64-bit Packed Library".

.PARAMETER Bitness
    Target LabVIEW bitness (32 or 64). Used when inferring the job name and as
    a fallback if the log does not specify the arch flag.

.PARAMETER Workspace
    Local workspace root that mirrors `${{ github.workspace }}`. Defaults to
    the current working directory.

.PARAMETER MinimumSupportedLVVersion
    Override the LabVIEW major version used when rebuilding.

.PARAMETER Major
.PARAMETER Minor
.PARAMETER Patch
.PARAMETER Build
    Version components passed to Build_lvlibp.ps1. When omitted the script
    attempts to extract the values from the job log.

.PARAMETER Commit
    Commit identifier to embed in the build metadata. Parsed from the log when
    not supplied explicitly.

.PARAMETER SkipBuild
    Skip invoking Build_lvlibp.ps1 (useful for dry runs or when only the rename
    step needs to be replayed).

.PARAMETER SkipRename
    Skip the rename step that produces lv_icon_{suffix}.lvlibp.

.PARAMETER CloseLabVIEW
    Invoke Close_LabVIEW.ps1 after the build (matches the CI job).
#>

[CmdletBinding(DefaultParameterSetName = 'Log')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [string]$RunId,

    [string]$LogPath,

    [ValidateSet(32, 64)]
    [int]$Bitness,

    [string]$JobName,

    [string]$Workspace = (Get-Location).Path,

    [int]$MinimumSupportedLVVersion,

    [int]$Major,
    [int]$Minor,
    [int]$Patch,
    [int]$Build,

    [string]$Commit,

    [switch]$SkipBuild,
    [switch]$SkipRename,
    [switch]$CloseLabVIEW,

    [switch]$Local,
    [switch]$SkipDevModeCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitHubCli {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Raw
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'gh'
    foreach ($arg in $Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "gh $($Arguments -join ' ') failed: $stderr"
    }

    if ($Raw) { return $stdout }
    return ($stdout | ConvertFrom-Json)
}

function Resolve-WorkspacePath {
    param([string]$Path)
    return (Resolve-Path -Path $Path -ErrorAction Stop).ProviderPath
}

function Parse-BuildLog {
    param([string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        throw "Log file not found at '$LogPath'."
    }

    $content = Get-Content -LiteralPath $LogPath -Raw

    $versionMatch = [regex]::Match($content, 'PPL Version:\s*(\d+)\.(\d+)\.(\d+)\.(\d+)')
    $commitMatch  = [regex]::Match($content, 'Commit:\s*([^\s]+)')
    $cliMatch     = [regex]::Match($content, 'g-cli\s+--lv-ver\s+(\d+)\s+--arch\s+(\d+)')

    $result = [ordered]@{
        Major   = $null
        Minor   = $null
        Patch   = $null
        Build   = $null
        Commit  = $null
        LvVer   = $null
        Bitness = $null
    }

    if ($versionMatch.Success) {
        $result.Major = [int]$versionMatch.Groups[1].Value
        $result.Minor = [int]$versionMatch.Groups[2].Value
        $result.Patch = [int]$versionMatch.Groups[3].Value
        $result.Build = [int]$versionMatch.Groups[4].Value
    }

    if ($commitMatch.Success) {
        $result.Commit = $commitMatch.Groups[1].Value
    }

    if ($cliMatch.Success) {
        $result.LvVer   = [int]$cliMatch.Groups[1].Value
        $result.Bitness = [int]$cliMatch.Groups[2].Value
    }

    return $result
}

$workspaceRoot = Resolve-WorkspacePath -Path $Workspace
$iconEditorRoot = Join-Path $workspaceRoot 'vendor/icon-editor'
$devModeModule  = Join-Path $workspaceRoot 'tools/icon-editor/IconEditorDevMode.psm1'
if (-not (Test-Path -LiteralPath $devModeModule -PathType Leaf)) {
    throw "IconEditorDevMode module not found at '$devModeModule'."
}
Import-Module $devModeModule -Force

if ($Local -and -not $PSBoundParameters.ContainsKey('Bitness')) {
    throw 'When using -Local, specify -Bitness so the suffix can be determined.'
}

if (-not $JobName -and -not $Local) {
    if ($Bitness) {
        $JobName = "Build $Bitness-bit Packed Library"
    } else {
        $JobName = 'Build 64-bit Packed Library'
    }
}

if ($RunId) {
    if (-not $LogPath) {
        $LogPath = Join-Path $workspaceRoot ("build-lvlibp-{0}.log" -f $RunId)
    }

    $runInfo = Invoke-GitHubCli -Arguments @('run', 'view', $RunId, '--json', 'jobs')
    $job = $runInfo.jobs | Where-Object { $_.name -eq $JobName } | Select-Object -First 1
    if (-not $job) {
        throw "Job '$JobName' not found in run $RunId."
    }

    $jobId = $null
    if ($job.PSObject.Properties['id']) {
        $jobId = $job.id
    } elseif ($job.PSObject.Properties['databaseId']) {
        $jobId = $job.databaseId
    }
    if (-not $jobId) {
        throw "Unable to determine job identifier for '$JobName' in run $RunId."
    }

    Write-Verbose ("Downloading job log for job {0} (run {1}) -> {2}" -f $JobName, $RunId, $LogPath)
    $logContent = Invoke-GitHubCli -Arguments @('run', 'view', $RunId, '--job', $jobId, '--log') -Raw
    Set-Content -LiteralPath $LogPath -Value $logContent -Encoding UTF8
}

$parsed = $null
if (-not $Local) {
    if (-not $LogPath) {
        throw 'LogPath is required when RunId is not supplied.'
    }

    $parsed = Parse-BuildLog -LogPath $LogPath

    if (-not $PSBoundParameters.ContainsKey('Major')) { $Major = $parsed.Major }
    if (-not $PSBoundParameters.ContainsKey('Minor')) { $Minor = $parsed.Minor }
    if (-not $PSBoundParameters.ContainsKey('Patch')) { $Patch = $parsed.Patch }
    if (-not $PSBoundParameters.ContainsKey('Build')) { $Build = $parsed.Build }
    if (-not $PSBoundParameters.ContainsKey('Commit')) { $Commit = $parsed.Commit }
    if (-not $PSBoundParameters.ContainsKey('MinimumSupportedLVVersion')) { $MinimumSupportedLVVersion = $parsed.LvVer }
    if (-not $PSBoundParameters.ContainsKey('Bitness')) { $Bitness = if ($parsed.Bitness) { $parsed.Bitness } else { 64 } }
}

foreach ($name in 'Major','Minor','Patch','Build') {
    $value = Get-Variable -Name $name -ValueOnly
    if ($null -eq $value) {
        throw "Unable to determine version component '$name' from the log; specify it explicitly."
    }
}
if (-not $Commit) { throw 'Unable to determine commit value from the log; specify -Commit.' }
if (-not $MinimumSupportedLVVersion) { throw 'Unable to determine LabVIEW version; specify -MinimumSupportedLVVersion.' }

$devCheckVersions = @([int]$MinimumSupportedLVVersion)
$devCheckBitness  = @([int]$Bitness)
if (-not $SkipDevModeCheck) {
    Assert-IconEditorDevelopmentToken `
        -RepoRoot $workspaceRoot `
        -IconEditorRoot $iconEditorRoot `
        -Versions $devCheckVersions `
        -Bitness $devCheckBitness `
        -Operation 'Replay-BuildLvlibp' | Out-Null
}

$suffix = switch ($Bitness) {
    32 { 'x86' }
    64 { 'x64' }
    default { "x$Bitness" }
}

$actionRoot = Join-Path $workspaceRoot '.github/actions'
$buildScript = Join-Path $actionRoot 'build-lvlibp/Build_lvlibp.ps1'
$closeScript = Join-Path $actionRoot 'close-labview/Close_LabVIEW.ps1'
$renameScript = Join-Path $actionRoot 'rename-file/Rename-file.ps1'

foreach ($scriptPath in @($buildScript, $renameScript)) {
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Required helper script not found at '$scriptPath'."
    }
}
if ($CloseLabVIEW.IsPresent -and -not (Test-Path -LiteralPath $closeScript -PathType Leaf)) {
    throw "Close_LabVIEW helper not found at '$closeScript'."
}

$iconEditorRoot = Join-Path $workspaceRoot 'vendor/icon-editor'
if (-not (Test-Path -LiteralPath $iconEditorRoot -PathType Container)) {
    throw "Icon editor root not found at '$iconEditorRoot'."
}

$targetPackedLib = Join-Path $iconEditorRoot 'resource\plugins\lv_icon.lvlibp'
$renamedPackedLib = Join-Path $iconEditorRoot ("resource\plugins\lv_icon_{0}.lvlibp" -f $suffix)

if (-not $SkipBuild.IsPresent) {
    Write-Host ("Rebuilding lvlibp via Build_lvlibp.ps1 (LabVIEW {0}, {1}-bit)..." -f $MinimumSupportedLVVersion, $Bitness) -ForegroundColor Cyan

    if (Test-Path -LiteralPath $targetPackedLib -PathType Leaf) {
        Remove-Item -LiteralPath $targetPackedLib -Force
    }

    $buildArgs = @(
        '-MinimumSupportedLVVersion', $MinimumSupportedLVVersion
        '-SupportedBitness',          $Bitness
        '-RelativePath',              $iconEditorRoot
        '-Major',                     $Major
        '-Minor',                     $Minor
        '-Patch',                     $Patch
        '-Build',                     $Build
        '-Commit',                    $Commit
    )

    & pwsh -NoLogo -NoProfile -File $buildScript @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Build_lvlibp.ps1 exited with code $LASTEXITCODE."
    }
}
else {
    Write-Host 'Skipping Build_lvlibp.ps1 (per -SkipBuild).' -ForegroundColor Yellow
}

if ($CloseLabVIEW.IsPresent) {
    & pwsh -NoLogo -NoProfile -File $closeScript -MinimumSupportedLVVersion $MinimumSupportedLVVersion -SupportedBitness $Bitness
}

if (-not $SkipRename.IsPresent) {
    if (-not (Test-Path -LiteralPath $targetPackedLib -PathType Leaf)) {
        throw "Expected packed library '$targetPackedLib' was not created."
    }

    if (Test-Path -LiteralPath $renamedPackedLib -PathType Leaf) {
        Remove-Item -LiteralPath $renamedPackedLib -Force
    }

    & pwsh -NoLogo -NoProfile -File $renameScript `
        -CurrentFilename $targetPackedLib `
        -NewFilename $renamedPackedLib

    if ($LASTEXITCODE -ne 0) {
        throw "Rename-file.ps1 exited with code $LASTEXITCODE."
    }

    Write-Host ("Packed library staged at {0}" -f $renamedPackedLib) -ForegroundColor Green
} else {
    Write-Host 'Skipping rename step (per -SkipRename).' -ForegroundColor Yellow
}

Write-Host 'Replay of Build Packed Library job completed.' -ForegroundColor Green
