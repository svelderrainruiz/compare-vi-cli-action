Describe 'Invoke-PesterTests Timeout Guard' -Tag 'Unit' {
  $script:dispatcher = Join-Path $PSScriptRoot '..' 'Invoke-PesterTests.ps1'

  It 'emits timedOut=true in JSON when timeout triggers (simulated)' {
    # Create a temp tests dir with a long-running test (simulate via Start-Sleep)
    $temp = Join-Path $PSScriptRoot 'tmp-timeout'
    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $testFile = Join-Path $temp 'Sleep.Tests.ps1'
    @(
      "Describe 'Sleep' {",
      "  It 'sleeps' { Start-Sleep -Seconds 30 }",
      "}"
    ) | Out-File -FilePath $testFile -Encoding utf8

    $results = Join-Path $temp 'results'
    $jsonSummary = 'pester-summary.json'

    $env:COMPARISON_ACTION_DEBUG='0'
    # Invoke dispatcher with very small timeout
    pwsh -File $dispatcher -TestsPath $temp -ResultsPath $results -JsonSummaryPath $jsonSummary -TimeoutMinutes 0.01 -IncludeIntegration false -EmitFailuresJsonAlways | Out-Null

    $summaryPath = Join-Path $results $jsonSummary
    Test-Path $summaryPath | Should -BeTrue
    $obj = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $obj.timedOut | Should -BeTrue
  }
}