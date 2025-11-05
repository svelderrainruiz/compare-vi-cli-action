#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-VipmCliPath {
    param(
        [string]$Executable = 'vipm'
    )

    if ($env:VIPM_CLI_PATH) {
        $candidate = $env:VIPM_CLI_PATH
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
        throw "VIPM CLI executable specified via VIPM_CLI_PATH was not found at '$candidate'."
    }

    $command = Get-Command -Name $Executable -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    throw "Unable to locate the VIPM CLI executable. Ensure 'vipm' is on PATH or set VIPM_CLI_PATH."
}

function Get-VipmCliInvocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('InstallVipc','BuildVip')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [hashtable]$Params
    )

    $binary = Resolve-VipmCliPath

    switch ($Operation) {
        'InstallVipc' {
            if (-not $Params.ContainsKey('VipcPath')) {
                throw 'VipcPath parameter is required for InstallVipc.'
            }
            if (-not $Params.ContainsKey('LabVIEWVersion')) {
                throw 'LabVIEWVersion parameter is required for InstallVipc.'
            }
            if (-not $Params.ContainsKey('LabVIEWBitness')) {
                throw 'LabVIEWBitness parameter is required for InstallVipc.'
            }

            $resolvedVipc = (Resolve-Path -LiteralPath $Params['VipcPath'] -ErrorAction Stop).ProviderPath
            $version = [string]$Params['LabVIEWVersion']
            $bitness = [string]$Params['LabVIEWBitness']

            $arguments = @('install', $resolvedVipc, '--labview-version', $version, '--labview-bitness', $bitness)
            if ($Params.ContainsKey('Upgrade') -and $Params['Upgrade']) {
                $arguments += '--upgrade'
            }

            return [pscustomobject]@{
                Toolchain = 'vipm-cli'
                Binary    = $binary
                Arguments = $arguments
            }
        }
        'BuildVip' {
            if (-not $Params.ContainsKey('BuildSpec')) {
                throw 'BuildSpec parameter is required for BuildVip.'
            }

            $resolvedSpec = (Resolve-Path -LiteralPath $Params['BuildSpec'] -ErrorAction Stop).ProviderPath
            $arguments = @('build', $resolvedSpec)

            if ($Params.ContainsKey('LabVIEWVersion') -and $Params['LabVIEWVersion']) {
                $arguments += @('--labview-version', [string]$Params['LabVIEWVersion'])
            }
            if ($Params.ContainsKey('LabVIEWBitness') -and $Params['LabVIEWBitness']) {
                $arguments += @('--labview-bitness', [string]$Params['LabVIEWBitness'])
            }
            if ($Params.ContainsKey('LvprojSpecification') -and $Params['LvprojSpecification']) {
                $arguments += @('--lvproj-spec', [string]$Params['LvprojSpecification'])
            }
            if ($Params.ContainsKey('LvprojTarget') -and $Params['LvprojTarget']) {
                $arguments += @('--lvproj-target', [string]$Params['LvprojTarget'])
            }

            return [pscustomobject]@{
                Toolchain = 'vipm-cli'
                Binary    = $binary
                Arguments = $arguments
            }
        }
    }
}

Export-ModuleMember -Function Resolve-VipmCliPath, Get-VipmCliInvocation
