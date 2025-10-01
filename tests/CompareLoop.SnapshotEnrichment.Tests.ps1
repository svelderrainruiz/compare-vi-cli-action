Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..') | Select-Object -ExpandProperty Path
Import-Module (Join-Path $repoRoot 'module' 'CompareLoop' 'CompareLoop.psd1') -Force

Describe 'Invoke-IntegrationCompareLoop metrics snapshot enrichment' -Tag 'Unit' {
  It 'emits schema v2 snapshots with dynamic percentiles and histogram when enabled' {
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("snaptest_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $base = Join-Path $tempDir 'Base.vi'; 'a' | Out-File -FilePath $base
    $head = Join-Path $tempDir 'Head.vi'; 'b' | Out-File -FilePath $head
    $snapPath = Join-Path $tempDir 'metrics.ndjson'
  $exec = { param($cli,$b,$h,$argList) $dur = 5 + ($script:__d++ % 5); Start-Sleep -Milliseconds $dur; return 0 }
    $script:__d = 0
    Invoke-IntegrationCompareLoop -Base $base -Head $head -MaxIterations 12 -IntervalSeconds 0 -CompareExecutor $exec -BypassCliValidation -SkipValidation -PassThroughPaths -Quiet -MetricsSnapshotEvery 3 -MetricsSnapshotPath $snapPath -CustomPercentiles '50,75,90,99' -IncludeSnapshotHistogram | Out-Null
    Test-Path $snapPath | Should -BeTrue
    $lines = Get-Content $snapPath
    $lines.Count | Should -Be 4 # iterations 3,6,9,12
    $obj = $lines | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($o in $obj) {
      $o.schema | Should -Be 'metrics-snapshot-v2'
      $o.percentiles | Should -Not -BeNullOrEmpty
      $o.requestedPercentiles | Should -Contain 75
      $o.percentiles.p75 | Should -Not -BeNullOrEmpty
      $o.histogram | Should -Not -BeNullOrEmpty
    }
  }
}