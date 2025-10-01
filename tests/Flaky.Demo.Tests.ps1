# Demonstrates a controllable flaky test that fails on first attempt then passes
# when ENABLE_FLAKY_DEMO=1 and an environment counter indicates first run.
# Used to showcase Watch-Pester -RerunFailedAttempts recovery classification.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Flaky Demo' -Tag 'Unit' {
  BeforeAll {
    # Initialize or increment an attempt counter in a temp file under tests/results
    $global:FlakyStatePath = Join-Path (Resolve-Path .).Path 'tests/results/flaky-demo-state.txt'
    if (-not (Test-Path $global:FlakyStatePath)) { '0' | Set-Content -LiteralPath $global:FlakyStatePath -Encoding UTF8 }
    $attempt = [int](Get-Content -LiteralPath $global:FlakyStatePath -Raw)
    $attempt++
    $attempt.ToString() | Set-Content -LiteralPath $global:FlakyStatePath -Encoding UTF8
    $script:CurrentAttempt = $attempt
  }

  It 'should be stable (or intentionally flaky first run)' {
    if ($env:ENABLE_FLAKY_DEMO -eq '1') {
      if ($script:CurrentAttempt -eq 1) {
        # Simulate a flaky failure only on the first attempt of the test file execution
        'Simulated first-attempt failure' | Should -Be 'Different'
      }
    }

    # Success path for subsequent retries or when demo disabled
    1 | Should -Be 1
  }
}
