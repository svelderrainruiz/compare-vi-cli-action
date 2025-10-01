# Diagnostic tests for Binding-MinRepro.ps1
# Purpose: Detect anomalous parameter binding behavior that drops positional argument for -Path
# Tags: Diagnostic, Unit

$ErrorActionPreference = 'Stop'

Describe 'Binding-MinRepro script parameter binding' -Tag 'Unit','Diagnostic' {

    It 'should exist at expected path' {
        $resolvedRoot = Resolve-Path -LiteralPath '.'
        Write-Host "[diag-test] Resolved root (inside It): $resolvedRoot" -ForegroundColor Cyan
        $scriptPath = Join-Path -Path $resolvedRoot -ChildPath 'tools/Binding-MinRepro.ps1'
        Write-Host "[diag-test] Computed scriptPath (inside It): $scriptPath" -ForegroundColor Cyan
        $scriptPath | Should -Not -BeNullOrEmpty
        $exists = Test-Path -LiteralPath $scriptPath -ErrorAction SilentlyContinue
        if (-not $exists) { Write-Host "[diag-test] WARNING path missing" -ForegroundColor Yellow }
        $exists | Should -BeTrue
    }

    Context 'Invocation with argument' {
        BeforeAll {
            # $TestDrive is only reliably available at run-time, not discovery.
            $script:TmpFile = Join-Path $TestDrive 'dummy.txt'
            Set-Content -LiteralPath $script:TmpFile -Value 'x'
        }
        It 'binds the positional Path argument and echoes it' {
            $resolvedRoot = Resolve-Path -LiteralPath '.'
            $scriptPath = Join-Path -Path $resolvedRoot -ChildPath 'tools/Binding-MinRepro.ps1'
            Write-Host "[diag-test] invocation scriptPath: $scriptPath" -ForegroundColor Cyan
            $out = & pwsh -NoProfile -File $scriptPath $script:TmpFile 2>&1
            $out | Should -Contain "[repro] Raw Input -Path: '$script:TmpFile'" -Because 'Script should echo bound Path'
            $out | Should -Not -Match "Path was NOT bound"
        }
    }

    Context 'Invocation without argument' {
        It 'warns when Path was not bound' {
            $resolvedRoot = Resolve-Path -LiteralPath '.'
            $scriptPath = Join-Path -Path $resolvedRoot -ChildPath 'tools/Binding-MinRepro.ps1'
            Write-Host "[diag-test] invocation scriptPath (no arg): $scriptPath" -ForegroundColor Cyan
            $out = & pwsh -NoProfile -File $scriptPath 2>&1
            $out | Should -Match 'Path was NOT bound'
        }
    }

    Context 'Invocation with non-existent path' {
        BeforeAll {
            $script:NonExist = Join-Path $TestDrive 'does-not-exist.xyz'
            # Do not create the file
        }
        It 'reports non-existent path warning' {
            $resolvedRoot = Resolve-Path -LiteralPath '.'
            $scriptPath = Join-Path -Path $resolvedRoot -ChildPath 'tools/Binding-MinRepro.ps1'
            Write-Host "[diag-test] invocation scriptPath (non-existent arg): $scriptPath" -ForegroundColor Cyan
            $out = & pwsh -NoProfile -File $scriptPath $script:NonExist 2>&1
            $out | Should -Match 'Provided Path does not exist'
        }
    }
}
