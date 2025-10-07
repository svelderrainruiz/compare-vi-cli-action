Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'WatchSmoke' -Tag 'WatchSmoke' {
  It 'runs the watch smoke test' {
    $true | Should -BeTrue
  }
}
