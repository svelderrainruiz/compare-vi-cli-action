Describe 'Agent-Wait utility' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Split-Path -Parent $here
    . (Join-Path $root 'tools' 'Agent-Wait.ps1')
  }

  It 'writes marker and results under provided ResultsDir and reports within margin' {
    $resultsDir = Join-Path $TestDrive 'agent-wait'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    $markerPath = Start-AgentWait -Reason 'unit-test' -ExpectedSeconds 1 -ToleranceSeconds 5 -ResultsDir $resultsDir
    $markerPath | Should -Not -BeNullOrEmpty

    Start-Sleep -Milliseconds 120
    $result = End-AgentWait -ResultsDir $resultsDir -ToleranceSeconds 5
    $result | Should -Not -BeNullOrEmpty

    $markerFile = Join-Path $resultsDir '_agent' 'wait-marker.json'
    $lastFile   = Join-Path $resultsDir '_agent' 'wait-last.json'
    $logFile    = Join-Path $resultsDir '_agent' 'wait-log.ndjson'

    (Test-Path $markerFile) | Should -BeTrue
    (Test-Path $lastFile)   | Should -BeTrue
    (Test-Path $logFile)    | Should -BeTrue

    $marker = Get-Content $markerFile -Raw | ConvertFrom-Json
    $marker.schema | Should -Be 'agent-wait/v1'
    $marker.reason | Should -Be 'unit-test'
    [int]$marker.expectedSeconds | Should -Be 1
    [int]$marker.toleranceSeconds | Should -Be 5

    $last = Get-Content $lastFile -Raw | ConvertFrom-Json
    $last.schema | Should -Be 'agent-wait-result/v1'
    [int]$last.elapsedSeconds | Should -BeGreaterOrEqual 0
    [int]$last.toleranceSeconds | Should -Be 5
    [int]$last.differenceSeconds | Should -BeGreaterOrEqual 0
    $last.withinMargin | Should -BeTrue
  }

  It 'reports outside margin when elapsed differs beyond tolerance' {
    $resultsDir = Join-Path $TestDrive 'agent-wait-2'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    # Expect 0s, use 0s tolerance, but sleep ~1.1s to ensure difference > tolerance
    $null = Start-AgentWait -Reason 'unit-test-outside' -ExpectedSeconds 0 -ToleranceSeconds 0 -ResultsDir $resultsDir
    Start-Sleep -Milliseconds 1100
    $result = End-AgentWait -ResultsDir $resultsDir -ToleranceSeconds 0
    $result | Should -Not -BeNullOrEmpty
    $result.withinMargin | Should -BeFalse
    [int]$result.differenceSeconds | Should -BeGreaterOrEqual 1
  }
}
