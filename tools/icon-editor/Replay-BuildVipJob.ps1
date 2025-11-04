#Requires -Version 7.0

<#
.SYNOPSIS
    Replays the GitHub Actions "Build VI Package" job locally.

.DESCRIPTION
    Fetches the job log (via gh) or accepts a pre-fetched log, extracts the
    display-information payload and version inputs, regenerates release notes,
    updates the VIPB metadata, and reruns the VI package build script. This
    allows rapid iteration without waiting for preceding CI stages.

.PARAMETER RunId
    The workflow run identifier to fetch. When supplied, the script queries
    GitHub for the job details and log content.

.PARAMETER LogPath
    Optional path to an existing job log. Use when you have already downloaded
    the log via 'gh run view ... --log'.

.PARAMETER JobName
    Name of the job to replay. Defaults to 'Build VI Package'.

.PARAMETER Workspace
    Local repository root mirroring ${{ github.workspace }}. Defaults to the
    current directory.

.PARAMETER ReleaseNotesPath
    Release notes file path (relative or absolute). Matches CI default of
    'Tooling/deployment/release_notes.md'.

.PARAMETER SkipReleaseNotes
    Skip regenerating release notes (assumes the file already exists).

.PARAMETER SkipVipbUpdate
    Skip calling Update-VipbDisplayInfo.ps1 (assumes VIPB already updated).

.PARAMETER SkipBuild
    Skip running build_vip.ps1 (helpful when debugging the metadata update only).

.PARAMETER CloseLabVIEW
    Invoke the Close_LabVIEW.ps1 helper after the build.

.PARAMETER DownloadArtifacts
    When supplied, downloads the run's artifacts (via gh run download) into a
    temporary directory and copies any lv_icon_*.lvlibp files into the expected
    resource/plugins folder.
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [string]$RunId,

    [Parameter()]
    [string]$LogPath,

    [string]$JobName = 'Build VI Package',

    [string]$Workspace = (Get-Location).Path,

    [string]$ReleaseNotesPath = 'Tooling/deployment/release_notes.md',

    [switch]$SkipReleaseNotes,
    [switch]$SkipVipbUpdate,
    [switch]$SkipBuild,
    [switch]$CloseLabVIEW,
    [switch]$DownloadArtifacts
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

$workspaceRoot = Resolve-WorkspacePath -Path $Workspace

if ($RunId) {
    Write-Verbose "Fetching job metadata for run $RunId"
    $runInfo = Invoke-GitHubCli -Arguments @('run', 'view', $RunId, '--json', 'jobs,headSha')
    $job = $runInfo.jobs | Where-Object { $_.name -eq $JobName }
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

    if (-not $LogPath) {
        $LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "build-vi-package-$RunId.log"
    }

    Write-Verbose "Downloading job log to $LogPath"
    $logContent = Invoke-GitHubCli -Arguments @('run', 'view', $RunId, '--job', $jobId, '--log') -Raw
    Set-Content -LiteralPath $LogPath -Value $logContent -Encoding UTF8

    if ($DownloadArtifacts) {
        $artifactDest = Join-Path $workspaceRoot ".replay-artifacts-$RunId"
        if (Test-Path -LiteralPath $artifactDest) {
            Remove-Item -LiteralPath $artifactDest -Recurse -Force
        }
        New-Item -ItemType Directory -Path $artifactDest | Out-Null

        Write-Verbose "Downloading artifacts to $artifactDest"
        $downloadArgs = @('run', 'download', $RunId, '--dir', $artifactDest)
        Invoke-GitHubCli -Arguments $downloadArgs | Out-Null

        $pluginsTarget = Join-Path $workspaceRoot 'resource\plugins'
        foreach ($file in Get-ChildItem -Path $artifactDest -Recurse -Filter 'lv_icon_*.lvlibp' -File) {
            $destinationPath = Join-Path $pluginsTarget $file.Name
            if (Test-Path -LiteralPath $destinationPath) {
                $existing = Get-Item -LiteralPath $destinationPath
                if ($existing -is [System.IO.DirectoryInfo]) {
                    Remove-Item -LiteralPath $destinationPath -Recurse -Force
                }
            }
            Copy-Item -LiteralPath $file.FullName -Destination $destinationPath -Force
        }
    }
}

if (-not $LogPath) {
    throw "A log file is required. Provide -RunId or -LogPath."
}

if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "Log file '$LogPath' does not exist."
}

$logLines = Get-Content -LiteralPath $LogPath

function Remove-AnsiEscapes {
    param([string]$Text)
    return ([regex]::Replace($Text, '\x1B\[[0-9;]*[A-Za-z]', ''))
}

function Get-VipbPackageFileName {
    param([string]$VipbPath)

    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($VipbPath)
    $node = $doc.SelectSingleNode('/VI_Package_Builder_Settings/Library_General_Settings/Package_File_Name')
    if (-not $node) {
        throw "Unable to locate Package_File_Name node in $VipbPath"
    }
    return $node.InnerText
}

$sanitizedLines = $logLines | ForEach-Object { Remove-AnsiEscapes $_ }
$jsonLine = $sanitizedLines | Where-Object { $_ -match 'DisplayInformationJSON' -or $_ -match 'display_information_json' } | Select-Object -Last 1
if (-not $jsonLine) {
    throw "Could not find the display-information payload in '$LogPath'."
}

$jsonMatch = [regex]::Match($jsonLine, "-DisplayInformationJSON\s+'(?<payload>\{.+\})'")
if (-not $jsonMatch.Success) {
    $jsonMatch = [regex]::Match($jsonLine, "display_information_json:\s+(?<payload>\{.+\})")
}
if (-not $jsonMatch.Success) {
    throw "Failed to parse display-information JSON from '$jsonLine'."
}

$displayInfo = $jsonMatch.Groups['payload'].Value | ConvertFrom-Json

$packageVersion = $displayInfo.'Package Version'
if (-not $packageVersion) {
    throw "DisplayInformation JSON did not contain 'Package Version'."
}

$intMajor = [int]$packageVersion.major
$intMinor = [int]$packageVersion.minor
$intPatch = [int]$packageVersion.patch
$intBuild = [int]$packageVersion.build

Push-Location $workspaceRoot
try {
    $vipbRelative = '.github/actions/build-vi-package/NI Icon editor.vipb'
    $vipbFullPath = Resolve-WorkspacePath -Path (Join-Path $workspaceRoot $vipbRelative)

    if ([System.IO.Path]::IsPathRooted($ReleaseNotesPath)) {
        $resolvedNotes = (Resolve-Path -Path $ReleaseNotesPath).ProviderPath
        if ($resolvedNotes.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $releaseNotesArgument = [System.IO.Path]::GetRelativePath($workspaceRoot, $resolvedNotes)
        } else {
            $releaseNotesArgument = $resolvedNotes
        }
        $releaseNotesFull = $resolvedNotes
    } else {
        $releaseNotesArgument = $ReleaseNotesPath
        $releaseNotesFull = Join-Path $workspaceRoot $ReleaseNotesPath
    }

    if (-not $SkipReleaseNotes) {
        Write-Host "Generating release notes at $releaseNotesFull"
        & pwsh -NoLogo -NoProfile -File '.github/actions/generate-release-notes/GenerateReleaseNotes.ps1' `
            -OutputPath $releaseNotesArgument
    }

    if (-not $SkipVipbUpdate) {
        Write-Host "Updating VIPB metadata via PowerShell helper"
        & pwsh -NoLogo -NoProfile -File '.github/actions/modify-vipb-display-info/Update-VipbDisplayInfo.ps1' `
            -SupportedBitness 64 `
            -RelativePath (Get-Location).Path `
            -VIPBPath $vipbRelative `
            -MinimumSupportedLVVersion 2023 `
            -LabVIEWMinorRevision 3 `
            -Major $intMajor `
            -Minor $intMinor `
            -Patch $intPatch `
            -Build $intBuild `
            -Commit ($RunId ?? 'local-replay') `
            -ReleaseNotesFile $releaseNotesArgument `
            -DisplayInformationJSON ($displayInfo | ConvertTo-Json -Depth 5)
    }

    if (-not $SkipBuild) {
        $packageName = Get-VipbPackageFileName -VipbPath $vipbFullPath
        $outputDir = Join-Path $workspaceRoot '.github/builds/VI Package'
        $expectedVip = Join-Path $outputDir ("{0}-{1}.{2}.{3}.{4}.vip" -f $packageName, $intMajor, $intMinor, $intPatch, $intBuild)
        if (Test-Path -LiteralPath $expectedVip) {
            Write-Host "Removing existing package at $expectedVip to avoid collisions."
            Remove-Item -LiteralPath $expectedVip -Force
        }

        Write-Host "Running build_vip.ps1 to produce VI Package"
        & pwsh -NoLogo -NoProfile -File '.github/actions/build-vi-package/build_vip.ps1' `
            -SupportedBitness 64 `
            -MinimumSupportedLVVersion 2023 `
            -LabVIEWMinorRevision 3 `
            -Major $intMajor `
            -Minor $intMinor `
            -Patch $intPatch `
            -Build $intBuild `
            -Commit ($RunId ?? 'local-replay') `
            -ReleaseNotesFile $releaseNotesArgument `
            -DisplayInformationJSON ($displayInfo | ConvertTo-Json -Depth 5)
    }

    if ($CloseLabVIEW) {
        Write-Host "Closing LabVIEW 2023 (64-bit)"
        & pwsh -NoLogo -NoProfile -File '.github/actions/close-labview/Close_LabVIEW.ps1' `
            -MinimumSupportedLVVersion 2023 `
            -SupportedBitness 64
    }
}
finally {
    Pop-Location
}

$vipOutputDir = Join-Path $workspaceRoot '.github/builds/VI Package'
Write-Host "Replay completed."
Write-Host " VIPB updated at $(Join-Path $workspaceRoot $vipbRelative)"
Write-Host " Generated .vip located under $vipOutputDir"
