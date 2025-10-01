# Restored RunSummary renderer tests (safe initialization pattern)
# These tests validate Convert-RunSummary/Render-RunSummary without triggering the previous
# discovery-time binding anomaly (all dynamic work occurs in BeforeAll / It blocks).

$ErrorActionPreference = 'Stop'

Describe 'RunSummary Renderer (Restored)' -Tag 'Unit','RunSummary' {
    BeforeAll {
    $repoRoot = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
    $script:ModulePath = Join-Path $repoRoot 'module/RunSummary/RunSummary.psm1'
        Import-Module $script:ModulePath -Force
        $script:TempSummary = Join-Path $TestDrive 'run-summary.json'
        $summaryObj = [pscustomobject]@{
            schema = 'compare-loop-run-summary-v1'
            iterations = 5
            diffCount = 2
            errorCount = 0
            averageSeconds = 1.23
            totalSeconds = 6.15
            quantileStrategy = 'Exact'
            mode = 'Single'
            requestedPercentiles = @( 'p50','p90','p99')
            percentiles = @{ p50 = 1.0; p90 = 1.5; p99 = 2.2 }
            histogram = @(0.5,1.0,1.5)
            rebaselineApplied = $false
        }
        $summaryObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:TempSummary -Encoding UTF8
    }

    It 'renders Markdown via Convert-RunSummary returning string' {
        $out = Convert-RunSummary -InputFile $script:TempSummary -Format Markdown -AsString
        $out | Should -Match '### Compare Loop Run Summary'
        $out | Should -Match '\| Iterations \| 5 \|'
        $out | Should -Match 'Percentiles'
    }

    It 'renders Text via Convert-RunSummary returning string' {
        $out = Convert-RunSummary -InputFile $script:TempSummary -Format Text -AsString
        $out | Should -Match '^Compare Loop Run Summary'
        $out | Should -Match 'Iterations\s*: 5'
        $out | Should -Match 'Percentiles:'
    }

    It 'renders via wrapper function Render-RunSummary (Markdown)' {
        $out = Render-RunSummary -InputFile $script:TempSummary -Format Markdown -AsString
        $out | Should -Match '\| Diffs \| 2 \|'
    }

    It 'errors on missing file' {
        $missing = Join-Path $TestDrive 'missing.json'
        $err = $null
        try {
            Convert-RunSummary -InputFile $missing -AsString | Out-Null
            'DidNotThrow' | Should -BeNullOrEmpty -Because 'Expected an exception for missing file'
        } catch {
            $err = $_
        }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Match 'Run summary file not found:'
    $err.Exception.Message | Should -Match 'missing.json'
    }
}
