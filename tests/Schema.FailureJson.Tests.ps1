Set-StrictMode -Version Latest

. "$PSScriptRoot/TestHelpers.Schema.ps1"

Describe 'Failure JSON Emission' -Tag 'Unit' {
  It 'writes failure JSON for single document assertion' {
    . "$PSScriptRoot/TestHelpers.Schema.ps1"
    $file = Join-Path $TestDrive 'bad.json'
    '{"schema":"loop-final-status-v1"}' | Set-Content -LiteralPath $file -Encoding UTF8
    $failPath = Join-Path $TestDrive 'fail.json'
    try { Assert-JsonShape -Path $file -Spec FinalStatus -FailureJsonPath $failPath -NoThrow | Out-Null } catch { }
    Test-Path $failPath | Should -BeTrue
    $data = Get-Content -LiteralPath $failPath -Raw | ConvertFrom-Json
    $data.spec | Should -Be 'FinalStatus'
    ($data.errors | Measure-Object).Count | Should -BeGreaterThan 0
  }
  It 'writes failure JSON for NDJSON assertion with multiple line errors' {
    . "$PSScriptRoot/TestHelpers.Schema.ps1"
    $file = Join-Path $TestDrive 'lines.ndjson'
    @(
      '{"schema":"metrics-snapshot-v2","iteration":1,"percentiles":{}}'
      '{"schema":"metrics-snapshot-v2","percentiles":{}}' # missing iteration
      'not json'
    ) | Set-Content -LiteralPath $file -Encoding UTF8
    $failPath = Join-Path $TestDrive 'failLines.json'
    try { Assert-NdjsonShapes -Path $file -Spec SnapshotV2 -FailureJsonPath $failPath -NoThrow | Out-Null } catch { }
    Test-Path $failPath | Should -BeTrue
    $data = Get-Content -LiteralPath $failPath -Raw | ConvertFrom-Json
    $data.spec | Should -Be 'SnapshotV2'
    ($data.lineErrors | Measure-Object).Count | Should -Be 2
  }
}
