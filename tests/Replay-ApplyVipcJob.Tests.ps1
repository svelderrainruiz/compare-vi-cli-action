#Requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'Replay-ApplyVipcJob helpers' -Tag 'Unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $repoRoot 'tools' 'icon-editor' 'Replay-ApplyVipcJob.ps1')
    }

    It 'parses matrix job titles' {
        $parsed = Parse-ApplyVipcJobTitle -Title 'Apply VIPC Dependencies (2025, 64)'
        $parsed | Should -Not -BeNullOrEmpty
        $parsed.Version | Should -Be '2025'
        $parsed.Bitness | Should -Be 64
    }

    It 'returns null for unexpected titles' {
        $parsed = Parse-ApplyVipcJobTitle -Title 'Other job'
        $parsed | Should -BeNullOrEmpty
    }

    It 'prefers explicit parameters over job title parsing' {
        $resolved = Resolve-ApplyVipcParameters `
            -RunId $null `
            -JobName 'Apply VIPC Dependencies (2025, 64)' `
            -Repository $null `
            -LogPath $null `
            -MinimumSupportedLVVersion '2021' `
            -VipLabVIEWVersion '2021' `
            -SupportedBitness 32

        $resolved.Version | Should -Be '2021'
        $resolved.VipVersion | Should -Be '2021'
        $resolved.Bitness | Should -Be 32
    }
}

