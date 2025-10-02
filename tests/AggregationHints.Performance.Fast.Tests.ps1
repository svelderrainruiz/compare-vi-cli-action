<#
 Fast performance guard for Get-AggregationHintsBlock.
 Purpose: very quick sanity check (CI friendly) that small-run performance stays tight.
 Dataset: 1,000 synthetic tests.
 Threshold: 120 ms (adjust if CI baseline proves higher; empirical local run expected well below this).
#>

Describe 'AggregationHints Performance (Fast)' -Tag 'Unit' {
  BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts' 'AggregationHints.Internal.ps1') }

  It 'aggregates 1k tests under 160ms' {
    $count = 1000
    $tags = 'UI','DB','Slow','Net','Cache','Auth'
    $tests = for ($i=0; $i -lt $count; $i++) {
      $tag = $tags[$i % $tags.Length]
      $dur = switch ($i % 3) { 0 { 0.05 } 1 { 1.2 } 2 { 3.4 } }
      [pscustomobject]@{ Path = "file$($i % 23).Tests.ps1"; Tags = @($tag); Duration = $dur }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Get-AggregationHintsBlock -Tests $tests
    $sw.Stop()
    $elapsed = $sw.Elapsed.TotalMilliseconds
  $elapsed | Should -BeLessThan 160 -Because "1k aggregation run should remain fast (was $([math]::Round($elapsed,2)) ms)"
  }
}
