<#
.SYNOPSIS
    Builds the Editor Packed Library (.lvlibp) using g-cli.

.DESCRIPTION
    Invokes the LabVIEW build specification "Editor Packed Library" through
    g-cli, embedding the provided version information and commit identifier.

.PARAMETER MinimumSupportedLVVersion
    LabVIEW version used for the build.

.PARAMETER SupportedBitness
    Bitness of the LabVIEW environment ("32" or "64").

.PARAMETER RelativePath
    Path to the repository root where the project file resides.

.PARAMETER Major
    Major version component for the PPL.

.PARAMETER Minor
    Minor version component for the PPL.

.PARAMETER Patch
    Patch version component for the PPL.

.PARAMETER Build
    Build number component for the PPL.

.PARAMETER Commit
    Commit hash or identifier recorded in the build.

.EXAMPLE
    .\Build_lvlibp.ps1 -MinimumSupportedLVVersion "2021" -SupportedBitness "64" -RelativePath "C:\labview-icon-editor" -Major 1 -Minor 0 -Patch 0 -Build 0 -Commit "Placeholder"
#>
param(
    [string]$MinimumSupportedLVVersion,
    [string]$SupportedBitness,
    [string]$RelativePath,
    [Int32]$Major,
    [Int32]$Minor,
    [Int32]$Patch,
    [Int32]$Build,
    [string]$Commit
)

Write-Output "PPL Version: $Major.$Minor.$Patch.$Build"
Write-Output "Commit: $Commit"

# Construct the command
$argumentList = @(
    'lvbuildspec',
    '--',
    '-v', ("{0}.{1}.{2}.{3}" -f $Major, $Minor, $Patch, $Build),
    '-p', (Join-Path $RelativePath 'lv_icon_editor.lvproj'),
    '-b', 'Editor Packed Library'
)

$binary = 'g-cli'
$binaryArgs = @(
    '--lv-ver', $MinimumSupportedLVVersion,
    '--arch',   $SupportedBitness
) + $argumentList

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')
$logsRoot = Join-Path $repoRoot 'tests\results\_agent\icon-editor\logs'
if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMddTHHmmssfff'
$logPath = Join-Path $logsRoot ("gcli-build-{0}-{1}.log" -f $SupportedBitness, $timestamp)

Write-Output "Executing the following command:"
Write-Output ("{0} {1}" -f $binary, ($binaryArgs -join ' '))

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $binary
foreach ($arg in $binaryArgs) {
    [void]$psi.ArgumentList.Add($arg)
}
$psi.WorkingDirectory = $RelativePath
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false

$process = [System.Diagnostics.Process]::Start($psi)
$stdout = $process.StandardOutput.ReadToEnd()
$stderr = $process.StandardError.ReadToEnd()
$process.WaitForExit()

$logLines = @(
    "# g-cli invocation"
    "Timestamp: $(Get-Date -Format o)"
    "WorkingDirectory: $($psi.WorkingDirectory)"
    "Command: $binary $($binaryArgs -join ' ')"
    "ExitCode: $($process.ExitCode)"
    "---- STDOUT ----"
    $stdout
    "---- STDERR ----"
    $stderr
)
Set-Content -LiteralPath $logPath -Value $logLines -Encoding UTF8

if ($stdout) {
    Write-Output $stdout
}
if ($stderr) {
    Write-Output $stderr
}

if ($process.ExitCode -ne 0) {
    & $binary '--lv-ver' $MinimumSupportedLVVersion '--arch' $SupportedBitness 'QuitLabVIEW' | Out-Null
    Write-Host "Build failed with exit code $($process.ExitCode). See $logPath for details."
    exit $process.ExitCode
}

Write-Host "Build succeeded."
exit 0

