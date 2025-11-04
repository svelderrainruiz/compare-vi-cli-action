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
    [string]$VIPCPath
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

# -------------------------
# 2) Resolve VIPM provider & execute
# -------------------------
$vipmModulePath = Join-Path $ResolvedRelativePath 'tools' 'Vipm.psm1'
if (-not (Test-Path -LiteralPath $vipmModulePath -PathType Leaf)) {
    Write-Error "VIPM module not found at '$vipmModulePath'."
    exit 1
}

Import-Module $vipmModulePath -Force

function Invoke-VipmProviderCommand {
    param(
        [Parameter(Mandatory)][string]$LabVIEWVersion
    )

    $params = @{
        vipcPath       = $ResolvedVIPCPath
        labviewVersion = $LabVIEWVersion
        labviewBitness = $SupportedBitness
    }

    try {
        $invocation = Get-VipmInvocation -Operation 'InstallVipc' -Params $params
    } catch {
        $hint = "Set VIPM_PATH/VIPM_EXE_PATH or configure configs/labview-paths*.json to point at VIPM.exe."
        throw "Unable to initialise VIPM provider: $($_.Exception.Message) $hint"
    }

    Write-Output ("Executing VIPM provider [{0}]: {1} {2}" -f $invocation.Provider, $invocation.Binary, ($invocation.Arguments -join ' '))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $invocation.Binary
    foreach ($arg in $invocation.Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.WorkingDirectory = (Split-Path -Parent $ResolvedVIPCPath)
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($stdout) { Write-Host $stdout.Trim() }
    if ($stderr) { Write-Host $stderr.Trim() }

    if ($proc.ExitCode -ne 0) {
        throw "VIPM provider exited with code $($proc.ExitCode)."
    }
}

$versionsToApply = [System.Collections.Generic.List[string]]::new()
$versionsToApply.Add([string]$MinimumSupportedLVVersion) | Out-Null
if ($VIP_LVVersion -and ($VIP_LVVersion -ne $MinimumSupportedLVVersion)) {
    $versionsToApply.Add([string]$VIP_LVVersion) | Out-Null
}

$uniqueVersions = $versionsToApply | Select-Object -Unique

foreach ($version in $uniqueVersions) {
    Write-Output ("Applying dependencies via VIPM for LabVIEW {0} ({1}-bit)..." -f $version, $SupportedBitness)
    try {
        Invoke-VipmProviderCommand -LabVIEWVersion $version
    } catch {
        Write-Error "Failed to apply dependencies for LabVIEW $version ($SupportedBitness-bit): $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "Successfully applied dependencies using VIPM provider."
