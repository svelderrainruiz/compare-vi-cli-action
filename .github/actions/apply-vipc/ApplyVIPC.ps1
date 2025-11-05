<#
.SYNOPSIS
    Applies a .vipc file to a given LabVIEW version/bitness.
    This version includes additional debug/verbose output.

.EXAMPLE
    .\applyvipc.ps1 -MinimumSupportedLVVersion "2021" -SupportedBitness "64" -RelativePath "C:\release\labview-icon-editor-fork" -VIP_LVVersion "2021" -Verbose
#>

[CmdletBinding()]  # Enables -Verbose and other common parameters
Param (
    [string]$MinimumSupportedLVVersion,
    [string]$VIP_LVVersion,
    [string]$SupportedBitness,
    [string]$RelativePath,
    [string]$VIPCPath,
    [ValidateSet('vipm-cli')]
    [string]$Toolchain = 'vipm-cli'
)

# Auto-detect the VIPC file if one isn't provided
if (-not $VIPCPath) {
    $vipcFiles = Get-ChildItem -Path $PSScriptRoot -Filter *.vipc
    if ($vipcFiles.Count -eq 0) {
        Write-Error "No .vipc file found in '$PSScriptRoot'."
        exit 1
    }
    if ($vipcFiles.Count -gt 1) {
        Write-Error "Multiple .vipc files found in '$PSScriptRoot'. Specify -VIPCPath."
        exit 1
    }
    $VIPCPath = $vipcFiles[0].FullName
    Write-Verbose "Auto-detected VIPCPath: $VIPCPath"
}

Write-Verbose "Script Name: $($MyInvocation.MyCommand.Definition)"
Write-Verbose "Parameters provided:"
Write-Verbose " - MinimumSupportedLVVersion: $MinimumSupportedLVVersion"
Write-Verbose " - VIP_LVVersion:             $VIP_LVVersion"
Write-Verbose " - SupportedBitness:          $SupportedBitness"
Write-Verbose " - RelativePath:              $RelativePath"
Write-Verbose " - VIPCPath:                  $VIPCPath"

# -------------------------
# 1) Resolve Paths & Validate
# -------------------------
try {
    Write-Verbose "Attempting to resolve the 'RelativePath'..."
    $ResolvedRelativePath = (Resolve-Path -Path $RelativePath -ErrorAction Stop).ProviderPath
    Write-Verbose "ResolvedRelativePath: $ResolvedRelativePath"

    Write-Verbose "Building full path for the .vipc file..."
    if ([System.IO.Path]::IsPathRooted($VIPCPath)) {
        $ResolvedVIPCPath = (Resolve-Path -Path $VIPCPath -ErrorAction Stop).ProviderPath
    } else {
        $ResolvedVIPCPath = (Resolve-Path -Path (Join-Path -Path $ResolvedRelativePath -ChildPath $VIPCPath) -ErrorAction Stop).ProviderPath
    }
    Write-Verbose "ResolvedVIPCPath:     $ResolvedVIPCPath"

    # Verify that the .vipc file actually exists
    Write-Verbose "Checking if the .vipc file exists at the resolved path..."
    if (-not (Test-Path $ResolvedVIPCPath)) {
        Write-Error "The .vipc file does not exist at '$ResolvedVIPCPath'."
        exit 1
    }
    Write-Verbose "The .vipc file was found successfully."
}
catch {
    Write-Error "Error resolving paths. Ensure RelativePath and VIPCPath are valid. Details: $($_.Exception.Message)"
    exit 1
}

$versionsToApply = [System.Collections.Generic.List[string]]::new()
$versionsToApply.Add([string]$MinimumSupportedLVVersion) | Out-Null
if ($VIP_LVVersion -and ($VIP_LVVersion -ne $MinimumSupportedLVVersion)) {
    $versionsToApply.Add([string]$VIP_LVVersion) | Out-Null
}

$uniqueVersions = $versionsToApply | Select-Object -Unique

function Invoke-ProcessInvocation {
    param(
        [Parameter(Mandatory)][pscustomobject]$Invocation,
        [string]$WorkingDirectory
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Invocation.Binary
    foreach ($arg in $Invocation.Arguments) {
        if ($null -ne $arg) {
            [void]$psi.ArgumentList.Add([string]$arg)
        }
    }
    if ($WorkingDirectory) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stdout) { Write-Host $stdout.Trim() }
    if ($stderr) { Write-Host $stderr.Trim() }

    if ($process.ExitCode -ne 0) {
        throw "Process exited with code $($process.ExitCode)."
    }
}

try {
    $vipmCliModulePath = Join-Path $ResolvedRelativePath 'tools' 'VipmCli.psm1'
    if (-not (Test-Path -LiteralPath $vipmCliModulePath -PathType Leaf)) {
        throw "VIPM CLI module not found at '$vipmCliModulePath'."
    }
    Import-Module $vipmCliModulePath -Force

    foreach ($version in $uniqueVersions) {
        Write-Output ("Applying dependencies via VIPM CLI for LabVIEW {0} ({1}-bit)..." -f $version, $SupportedBitness)
        $params = @{
            VipcPath       = $ResolvedVIPCPath
            LabVIEWVersion = $version
            LabVIEWBitness = $SupportedBitness
        }
        $invocation = Get-VipmCliInvocation -Operation 'InstallVipc' -Params $params
        Write-Output ("Executing VIPM CLI [{0}]: {1} {2}" -f $invocation.Provider, $invocation.Binary, ($invocation.Arguments -join ' '))
        Invoke-ProcessInvocation -Invocation $invocation -WorkingDirectory (Split-Path -Parent $ResolvedVIPCPath)
    }
} catch {
    Write-Error ("Failed to apply VIPC dependencies using VIPM CLI: {0}" -f $_.Exception.Message)
    exit 1
}

Write-Host "Successfully applied dependencies using VIPM CLI."
