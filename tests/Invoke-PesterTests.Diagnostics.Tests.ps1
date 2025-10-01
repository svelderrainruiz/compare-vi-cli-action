Describe 'Dispatcher Failure Diagnostics (Synthetic)' -Tag 'Unit' {
  Context 'Synthetic failing test to exercise diagnostics' {
    It 'produces a controlled failure (for manual diagnostic verification)' -Skip:(-not $env:ENABLE_DIAGNOSTIC_FAIL) {
      # This assertion intentionally fails when ENABLE_DIAGNOSTIC_FAIL is set.
      # It allows developers to observe enhanced failure output without altering core tests.
      1 | Should -Be 2
    }
    It 'passes when diagnostics not forced' -Skip:$env:ENABLE_DIAGNOSTIC_FAIL {
      1 | Should -Be 1
    }
  }
}
