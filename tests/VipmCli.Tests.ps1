#Requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'VipmCli wrapper' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $repoRoot 'tools\VipmCli.psm1') -Force
    }

    It 'builds install invocation for a VIPC with version + bitness' {
        InModuleScope VipmCli {
            $vipcPath = Join-Path $TestDrive 'sample.vipc'
            Set-Content -LiteralPath $vipcPath -Value 'payload' -Encoding UTF8

            Mock -CommandName Resolve-VipmCliPath -ModuleName VipmCli -MockWith { 'C:\tools\vipm.exe' }

            $result = Get-VipmCliInvocation -Operation 'InstallVipc' -Params @{
                VipcPath       = $vipcPath
                LabVIEWVersion = '2021'
                LabVIEWBitness = '64'
            }

            $result.Toolchain | Should -Be 'vipm-cli'
            $result.Binary    | Should -Be 'C:\tools\vipm.exe'
            $result.Arguments | Should -Be @(
                'install',
                (Resolve-Path -LiteralPath $vipcPath).ProviderPath,
                '--labview-version','2021',
                '--labview-bitness','64'
            )
        }
    }

    It 'builds build invocation with optional project selectors' {
        InModuleScope VipmCli {
            $vipbPath = Join-Path $TestDrive 'NI Icon editor.vipb'
            Set-Content -LiteralPath $vipbPath -Value '<vipb />' -Encoding UTF8

            Mock -CommandName Resolve-VipmCliPath -ModuleName VipmCli -MockWith { 'D:\vipm\vipm.exe' }

            $result = Get-VipmCliInvocation -Operation 'BuildVip' -Params @{
                BuildSpec          = $vipbPath
                LabVIEWVersion     = 2025
                LabVIEWBitness     = 64
                LvprojSpecification = 'MySpec'
                LvprojTarget        = 'My Computer'
            }

            $result.Toolchain | Should -Be 'vipm-cli'
            $result.Binary    | Should -Be 'D:\vipm\vipm.exe'
            $result.Arguments | Should -Be @(
                'build',
                (Resolve-Path -LiteralPath $vipbPath).ProviderPath,
                '--labview-version','2025',
                '--labview-bitness','64',
                '--lvproj-spec','MySpec',
                '--lvproj-target','My Computer'
            )
        }
    }
}
