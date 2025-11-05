#Requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'IconEditorPackage helpers' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path $repoRoot 'tools\icon-editor\IconEditorPackage.psm1'
        Import-Module $modulePath -Force

        Import-Module (Join-Path $repoRoot 'tools\VipmCli.psm1') -Force

        $script:VipbPath = Join-Path $repoRoot '.github\actions\build-vi-package\NI Icon editor.vipb'
        if (-not (Test-Path -LiteralPath $script:VipbPath -PathType Leaf)) {
            throw "Fixture VIPB not found at '$script:VipbPath'."
        }

        $script:WorkspaceRoot = $repoRoot
    }

    It 'extracts the package file name from the VIPB' {
        Get-IconEditorPackageName -VipbPath $script:VipbPath | Should -Be 'NI_Icon_editor'
    }

    It 'computes a deterministic package path inside the default builds folder' {
        $expected = Join-Path $script:WorkspaceRoot '.github\builds\VI Package\NI_Icon_editor-0.6.0.1213.vip'
        $path = Get-IconEditorPackagePath -VipbPath $script:VipbPath -Major 0 -Minor 6 -Patch 0 -Build 1213 -WorkspaceRoot $script:WorkspaceRoot

        $path | Should -Be $expected

        # Idempotency: a second call should return the identical path without mutating state.
        Get-IconEditorPackagePath -VipbPath $script:VipbPath -Major 0 -Minor 6 -Patch 0 -Build 1213 -WorkspaceRoot $script:WorkspaceRoot |
            Should -Be $expected
    }

    It 'supports overriding the output directory when computing package path' {
        $customDir = Join-Path $TestDrive 'packages'
        $path = Get-IconEditorPackagePath -VipbPath $script:VipbPath -Major 1 -Minor 2 -Patch 3 -Build 4 -WorkspaceRoot $script:WorkspaceRoot -OutputDirectory $customDir

        $path | Should -Be (Join-Path $customDir 'NI_Icon_editor-1.2.3.4.vip')
    }

    Context 'Process helpers' {
        It 'captures stdout, stderr, and warnings from build process failure' {
            $scriptPath = Join-Path $TestDrive 'emit-warning.ps1'
            @'
Write-Output "[WARN] simulated warning"
[Console]::Error.WriteLine("simulated error")
exit 42
'@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8
            try {
                $result = Invoke-IconEditorProcess -Binary (Get-Command pwsh).Source -Arguments @('-NoLogo','-NoProfile','-File',$scriptPath) -Quiet
                $result.ExitCode | Should -Be 42
                $result.StdErr | Should -Match 'simulated error'
                ($result.Warnings -join ' ') | Should -Match 'simulated warning'
            } finally {
                Remove-Item -LiteralPath $scriptPath -ErrorAction SilentlyContinue
            }
        }

        It 'reports exit code and warnings for successful runs' {
            $scriptPath = Join-Path $TestDrive 'emit-success.ps1'
            @'
Write-Output "[WARN] mock build warning"
exit 0
'@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8
            try {
                $result = Invoke-IconEditorProcess -Binary (Get-Command pwsh).Source -Arguments @('-NoLogo','-NoProfile','-File',$scriptPath) -Quiet
                $result.ExitCode | Should -Be 0
                $result.Warnings | Should -Contain '[WARN] mock build warning'
                $result.DurationSeconds -ge 0 | Should -BeTrue
            } finally {
                Remove-Item -LiteralPath $scriptPath -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Package artifact helper' {
        It 'returns metadata when the package exists' {
            $packagePath = Join-Path $TestDrive 'sample.vip'
            Set-Content -LiteralPath $packagePath -Value 'payload' -Encoding UTF8

            $artifact = Confirm-IconEditorPackageArtifact -PackagePath $packagePath
            $artifact.PackagePath | Should -Be (Resolve-Path -LiteralPath $packagePath).Path
            $artifact.SizeBytes | Should -Be ((Get-Item -LiteralPath $packagePath).Length)
            $artifact.Sha256 | Should -Be ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash)
        }

        It 'throws when the expected package is missing' {
            { Confirm-IconEditorPackageArtifact -PackagePath (Join-Path $TestDrive 'missing.vip') } | Should -Throw
        }
    }

    Context 'VI Server snapshot captures' {
        It 'returns a structured snapshot even when LabVIEW 2021 is unavailable' {
            $snapshot = Get-IconEditorViServerSnapshot -Version 2021 -Bitness 64 -WorkspaceRoot $script:WorkspaceRoot
            $snapshot | Should -Not -BeNullOrEmpty
            $snapshot.Version | Should -Be 2021
            $snapshot.Bitness | Should -Be 64

            $allowedStatuses = @('ok','missing','missing-ini','vendor-tools-missing','error')
            $snapshot.Status | Should -BeIn $allowedStatuses
        }
    }

    Context 'Invoke-IconEditorVipBuild toolchain flow' {
        BeforeAll {
            $script:fakeBuildScript = Join-Path $TestDrive 'fake-build.ps1'
            $fakeScriptContent = @'
param()
$packagePath = [Environment]::GetEnvironmentVariable('ICON_EDITOR_EXPECTED_PACKAGE')
if (-not [string]::IsNullOrWhiteSpace($packagePath)) {
    $dir = Split-Path -Parent $packagePath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $packagePath -Value 'mock package' -Encoding UTF8 -Force
}
Write-Output "[WARN] mock vipm-cli warning"
exit 0
'@
            Set-Content -LiteralPath $script:fakeBuildScript -Value $fakeScriptContent -Encoding UTF8
        }

        AfterAll {
            Remove-Item -LiteralPath $script:fakeBuildScript -ErrorAction SilentlyContinue
        }

        It 'invokes vipm-cli toolchain and records metadata' {
            $expected = Get-IconEditorPackagePath -VipbPath $script:VipbPath -Major 0 -Minor 6 -Patch 0 -Build 1302 -WorkspaceRoot $script:WorkspaceRoot
            $prevEnv = [Environment]::GetEnvironmentVariable('ICON_EDITOR_EXPECTED_PACKAGE')
            try {
                [Environment]::SetEnvironmentVariable('ICON_EDITOR_EXPECTED_PACKAGE', $expected, [System.EnvironmentVariableTarget]::Process)

                Mock -CommandName Get-VipmCliInvocation -ModuleName IconEditorPackage -MockWith {
                    [pscustomobject]@{
                        Toolchain = 'vipm-cli'
                        Binary    = (Get-Command pwsh).Source
                        Arguments = @('-NoLogo','-NoProfile','-File',$script:fakeBuildScript)
                    }
                } -Verifiable

                $result = Invoke-IconEditorVipBuild `
                    -VipbPath $script:VipbPath `
                    -Major 0 `
                    -Minor 6 `
                    -Patch 0 `
                    -Build 1302 `
                    -SupportedBitness 64 `
                    -MinimumSupportedLVVersion 2025 `
                    -LabVIEWMinorRevision 3 `
                    -ReleaseNotesPath 'Tooling/deployment/release_notes.md' `
                    -WorkspaceRoot $script:WorkspaceRoot `
                    -Toolchain 'vipm-cli'

                Assert-MockCalled -CommandName Get-VipmCliInvocation -ModuleName IconEditorPackage -Times 1
            } finally {
                if ($null -ne $prevEnv) {
                    [Environment]::SetEnvironmentVariable('ICON_EDITOR_EXPECTED_PACKAGE', $prevEnv, [System.EnvironmentVariableTarget]::Process)
                } else {
                    [Environment]::SetEnvironmentVariable('ICON_EDITOR_EXPECTED_PACKAGE', $null, [System.EnvironmentVariableTarget]::Process)
                }
            }

            $result.Toolchain | Should -Be 'vipm-cli'
            $result.PackagePath | Should -Be $expected
            Test-Path -LiteralPath $expected | Should -BeTrue
            $result.ToolchainBinary | Should -Be (Get-Command pwsh).Source
            $result.PackageSha256 | Should -Be ((Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash)
            $result.PackageSize | Should -Be ((Get-Item -LiteralPath $expected).Length)
            if (Test-Path -LiteralPath $expected) {
                Remove-Item -LiteralPath $expected -Force
            }
        }

        It 'throws when vipm-cli exits non-zero and surfaces stderr' {
            Mock -CommandName Get-VipmCliInvocation -ModuleName IconEditorPackage -MockWith {
                [pscustomobject]@{
                    Toolchain = 'vipm-cli'
                    Binary    = 'C:\vipm\vipm.exe'
                    Arguments = @('build','spec.vipb')
                }
            } -Verifiable

            Mock -CommandName Invoke-IconEditorProcess -ModuleName IconEditorPackage -MockWith {
                [pscustomobject]@{
                    Binary          = 'C:\vipm\vipm.exe'
                    Arguments       = @('build','spec.vipb')
                    ExitCode        = 1
                    StdOut          = ''
                    StdErr          = 'ERROR: vipb.vi missing'
                    Output          = 'ERROR: vipb.vi missing'
                    DurationSeconds = 0.1
                    Warnings        = @('ERROR: vipb.vi missing')
                }
            } -Verifiable

            Mock -CommandName Confirm-IconEditorPackageArtifact -ModuleName IconEditorPackage -MockWith {
                throw 'Confirm-IconEditorPackageArtifact should not be called on failure.'
            }

            { Invoke-IconEditorVipBuild `
                -VipbPath $script:VipbPath `
                -Major 0 `
                -Minor 6 `
                -Patch 0 `
                -Build 1303 `
                -SupportedBitness 64 `
                -MinimumSupportedLVVersion 2025 `
                -LabVIEWMinorRevision 3 `
                -ReleaseNotesPath 'Tooling/deployment/release_notes.md' `
                -WorkspaceRoot $script:WorkspaceRoot `
                -Toolchain 'vipm-cli' } | Should -Throw -ErrorId *

            Assert-MockCalled -CommandName Invoke-IconEditorProcess -ModuleName IconEditorPackage -Times 1
            Assert-MockCalled -CommandName Confirm-IconEditorPackageArtifact -ModuleName IconEditorPackage -Times 0 -Exactly
        }

        It 'captures vipm-cli warnings emitted during the build' {
            Mock -CommandName Get-VipmCliInvocation -ModuleName IconEditorPackage -MockWith {
                [pscustomobject]@{
                    Toolchain = 'vipm-cli'
                    Binary    = (Get-Command pwsh).Source
                    Arguments = @('-NoLogo','-NoProfile','-File',$script:fakeBuildScript)
                }
            } -Verifiable

            Mock -CommandName Invoke-IconEditorProcess -ModuleName IconEditorPackage -MockWith {
                [pscustomobject]@{
                    Binary          = (Get-Command pwsh).Source
                    Arguments       = @('-NoLogo','-NoProfile','-File',$script:fakeBuildScript)
                    ExitCode        = 0
                    StdOut          = ''
                    StdErr          = ''
                    Output          = ''
                    DurationSeconds = 0.2
                    Warnings        = @('[WARN] mock vipm-cli warning')
                }
            } -Verifiable

            Mock -CommandName Confirm-IconEditorPackageArtifact -ModuleName IconEditorPackage -MockWith {
                [pscustomobject]@{
                    PackagePath       = 'C:\packages\icon.vip'
                    Sha256            = 'abc'
                    SizeBytes         = 100
                    LastWriteTimeUtc  = (Get-Date).ToUniversalTime()
                }
            }

            $result = Invoke-IconEditorVipBuild `
                -VipbPath $script:VipbPath `
                -Major 0 `
                -Minor 6 `
                -Patch 0 `
                -Build 1304 `
                -SupportedBitness 64 `
                -MinimumSupportedLVVersion 2025 `
                -LabVIEWMinorRevision 3 `
                -ReleaseNotesPath 'Tooling/deployment/release_notes.md' `
                -WorkspaceRoot $script:WorkspaceRoot `
                -Toolchain 'vipm-cli'

            Assert-MockCalled -CommandName Get-VipmCliInvocation -ModuleName IconEditorPackage -Times 1
            Assert-MockCalled -CommandName Invoke-IconEditorProcess -ModuleName IconEditorPackage -Times 1
            $result.Warnings | Should -Contain '[WARN] mock vipm-cli warning'
        }
    }
}

