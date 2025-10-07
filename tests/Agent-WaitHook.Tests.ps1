Describe 'Agent-WaitHook profile' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Split-Path -Parent $here
    . (Join-Path $root 'tools' 'Agent-Wait.ps1')
    . (Join-Path $root 'tools' 'Agent-WaitHook.Profile.ps1')
  }

  It 'auto-ends on next prompt invocation' {
    $resultsDir = Join-Path $TestDrive 'hook'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    Enable-AgentWaitHook -Reason 'hook-test' -ExpectedSeconds 0 -ToleranceSeconds 5 -ResultsDir $resultsDir -Id 'hook1'
    # Simulate delay and prompt draw
    Start-Sleep -Milliseconds 200
    $null = & Prompt
    # Validate last exists
    $sessionDir = Join-Path (Join-Path $resultsDir '_agent') (Join-Path 'sessions' 'hook1')
    $last = Join-Path $sessionDir 'wait-last.json'
    (Test-Path $last) | Should -BeTrue
    $j = Get-Content $last -Raw | ConvertFrom-Json
    $j.withinMargin | Should -BeTrue
    Disable-AgentWaitHook
  }
}
