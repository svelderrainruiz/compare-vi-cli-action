# Tests for Invoke-WithFunctionShadow helper

Describe 'Invoke-WithFunctionShadow' -Tag 'Unit' {
  BeforeAll {
    . "$PSScriptRoot/support/FunctionShadowing.ps1"
  }

  It 'shadows an existing cmdlet and restores it' {
    $result = Invoke-WithFunctionShadow -Name Get-Date -Definition {
      param()
      # Return a fixed date
      [datetime]'2001-01-01'
    } -Body {
      Get-Date
    }

    $result | Should -Be ([datetime]'2001-01-01')

    # After the shadow, Get-Date should again return (roughly) now and be a CmdletInfo
    $post = Get-Date
    ($post -gt (Get-Date).AddMinutes(-1)) | Should -BeTrue
    (Get-Command Get-Date).CommandType | Should -Be 'Cmdlet'
  }

  It 'supports multiple invocations without leakage' {
    1..3 | ForEach-Object {
      $val = Invoke-WithFunctionShadow -Name Get-Random -Definition {
        param()
        return 42
      } -Body { Get-Random }
      $val | Should -Be 42
    }
    # After loops, Get-Random should not be permanently 42 (highly unlikely to be 42 three times)
    $natural = Get-Random
    $natural | Should -Not -Be 42
  }

  It 'propagates exceptions from body while still restoring' {
    $originalType = (Get-Command Get-Item).CommandType
    try {
      Invoke-WithFunctionShadow -Name Get-Item -Definition {
        param([string]$Path) ; throw 'boom'
      } -Body { Get-Item 'foo' }
      throw 'Should have thrown'
    } catch {
      $_.Exception.Message | Should -Be 'boom'
    }
    # Ensure Get-Item is still available as original cmdlet
    (Get-Command Get-Item).CommandType | Should -Be $originalType
  }
}
