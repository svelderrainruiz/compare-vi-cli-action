Describe 'Invoke-PesterTests Timeout Guard' -Tag 'Unit' {
  BeforeAll {
    . (Join-Path $PSScriptRoot '_TestPathHelper.ps1')
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:dispatcher = Join-Path $repoRoot 'Invoke-PesterTests.ps1'
  }

  It 'emits timedOut=true in JSON when timeout triggers (simulated)' {
    # Create a temp tests dir with a long-running test (simulate via Start-Sleep)
    $temp = Join-Path $PSScriptRoot 'tmp-timeout'
    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $testFile = Join-Path $temp 'Sleep.Tests.ps1'
    @(
      "Describe 'Sleep' {",
      "  It 'sleeps' { Start-Sleep -Seconds 3 }",
      "}"
    ) | Out-File -FilePath $testFile -Encoding utf8

    $results = Join-Path $temp 'results'
    $jsonSummary = 'pester-summary.json'

    $env:COMPARISON_ACTION_DEBUG='0'
    # Invoke dispatcher with very small timeout
    $previousFast = $env:FAST_PESTER
    $env:FAST_PESTER = '0'
    try {
      pwsh -File $script:dispatcher -TestsPath $temp -ResultsPath $results -JsonSummaryPath $jsonSummary -TimeoutSeconds 1 -IntegrationMode exclude -EmitFailuresJsonAlways | Out-Null

      $summaryPath = Join-Path $results $jsonSummary
      Test-Path $summaryPath | Should -BeTrue
      $obj = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
      $obj.total | Should -Be 0
      $obj.errors | Should -BeGreaterOrEqual 1
      $obj.timedOut | Should -BeTrue
      $obj.meanTest_ms | Should -Be $null
      $obj.p95Test_ms | Should -Be $null
      $obj.maxTest_ms | Should -Be $null

      $partialLog = Join-Path $results 'pester-partial.log'
      Test-Path -LiteralPath $partialLog | Should -BeTrue
    } finally {
      if ($null -ne $previousFast) { $env:FAST_PESTER = $previousFast }
      else { Remove-Item Env:\FAST_PESTER -ErrorAction SilentlyContinue }
      if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
  }
}
