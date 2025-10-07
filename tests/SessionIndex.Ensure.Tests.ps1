Describe 'Ensure-SessionIndex' -Tag 'Unit' {
  It 'creates a fallback session-index.json with status ok from pester-summary.json' {
    # Arrange
    $td = Join-Path $TestDrive 'results'
    New-Item -ItemType Directory -Force -Path $td | Out-Null
    $ps = @{
      total = 2; passed = 2; failed = 0; errors = 0; skipped = 0; duration_s = 1.23; schemaVersion = '1.0.0'
    } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $td 'pester-summary.json') -Value $ps -Encoding UTF8

    $root = (Get-Location).Path
    & (Join-Path $root 'tools/Ensure-SessionIndex.ps1') -ResultsDir $td -SummaryJson 'pester-summary.json'

    # Assert
    $idxPath = Join-Path $td 'session-index.json'
    Test-Path -LiteralPath $idxPath | Should -BeTrue
    $idx = Get-Content -LiteralPath $idxPath -Raw | ConvertFrom-Json
    $idx.schema | Should -Be 'session-index/v1'
    $idx.status | Should -Be 'ok'
    $idx.summary.total | Should -Be 2
    $idx.summary.passed | Should -Be 2
    $idx.summary.failed | Should -Be 0
    $idx.summary.errors | Should -Be 0
    $idx.summary.skipped | Should -Be 0
  }
}

