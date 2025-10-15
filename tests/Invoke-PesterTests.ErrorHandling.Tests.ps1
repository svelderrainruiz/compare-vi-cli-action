Describe 'Invoke-PesterTests failure handling (split)' -Tag 'Unit' {
  It 'moved to split test files' {
    # Coverage moved to:
    # - tests/Invoke-PesterTests.ErrorHandling.FileGuard.Tests.ps1
    # - tests/Invoke-PesterTests.ErrorHandling.DirectoryGuard.Tests.ps1
    $true | Should -BeTrue
  }
}
