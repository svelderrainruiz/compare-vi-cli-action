Describe 'Agent-Wait utility' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Split-Path -Parent $here
    . (Join-Path $root 'tools' 'Agent-Wait.ps1')
    . (Join-Path $here '_TestPathHelper.ps1')
  }

  It 'writes marker and results under provided ResultsDir and reports within margin' {
    $resultsDir = Join-Path $TestDrive 'agent-wait'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    $markerPath = Start-AgentWait -Reason 'unit-test' -ExpectedSeconds 1 -ToleranceSeconds 5 -ResultsDir $resultsDir -Id 'ut1'
    $markerPath | Should -Not -BeNullOrEmpty

    Invoke-TestSleep -Milliseconds 120 -FastMilliseconds 10
    $result = End-AgentWait -ResultsDir $resultsDir -ToleranceSeconds 5 -Id 'ut1'
    $result | Should -Not -BeNullOrEmpty

    $sessionDir = Join-Path (Join-Path $resultsDir '_agent') (Join-Path 'sessions' 'ut1')
    $markerFile = Join-Path $sessionDir 'wait-marker.json'
    $lastFile   = Join-Path $sessionDir 'wait-last.json'
    $logFile    = Join-Path $sessionDir 'wait-log.ndjson'

    (Test-Path $markerFile) | Should -BeTrue
    (Test-Path $lastFile)   | Should -BeTrue
    (Test-Path $logFile)    | Should -BeTrue

    $marker = Get-Content $markerFile -Raw | ConvertFrom-Json
    $marker.schema | Should -Be 'agent-wait/v1'
    $marker.reason | Should -Be 'unit-test'
    $marker.id | Should -Be 'ut1'
    [int]$marker.expectedSeconds | Should -Be 1
    [int]$marker.toleranceSeconds | Should -Be 5

    $last = Get-Content $lastFile -Raw | ConvertFrom-Json
    $last.schema | Should -Be 'agent-wait-result/v1'
    [int]$last.elapsedSeconds | Should -BeGreaterOrEqual 0
    [int]$last.toleranceSeconds | Should -Be 5
    $last.id | Should -Be 'ut1'
    [int]$last.differenceSeconds | Should -BeGreaterOrEqual 0
    $last.withinMargin | Should -BeTrue
  }

  It 'reports outside margin when elapsed differs beyond tolerance' {
    $resultsDir = Join-Path $TestDrive 'agent-wait-2'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    # Expect 0s, use 0s tolerance, but sleep ~1.1s to ensure difference > tolerance
    if (Test-IsFastMode) {
      $null = Start-AgentWait -Reason 'unit-test-outside' -ExpectedSeconds 0 -ToleranceSeconds 0 -ResultsDir $resultsDir
      Invoke-TestSleep -Milliseconds 120 -FastMilliseconds 20
      $result = End-AgentWait -ResultsDir $resultsDir -ToleranceSeconds 0
      $result | Should -Not -BeNullOrEmpty
      $result.withinMargin | Should -BeFalse
    } else {
      $null = Start-AgentWait -Reason 'unit-test-outside' -ExpectedSeconds 0 -ToleranceSeconds 0 -ResultsDir $resultsDir
      Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds 1100
      $result = End-AgentWait -ResultsDir $resultsDir -ToleranceSeconds 0
      $result | Should -Not -BeNullOrEmpty
      $result.withinMargin | Should -BeFalse
      [int]$result.differenceSeconds | Should -BeGreaterOrEqual 1
    }
  }
}
