# Tests for Test-PesterAvailable probe function
# These are pure unit tests that mock Get-Module to validate the probe logic.

Describe 'Test-PesterAvailable' -Tag 'Unit' {
  BeforeAll {
    . "$PSScriptRoot/support/FunctionShadowing.ps1"
    if (-not (Get-Command Test-PesterAvailable -ErrorAction SilentlyContinue)) {
      function Test-PesterAvailable {
        $mods = Get-Module -ListAvailable -Name Pester | Where-Object { $_ -and $_.Version -ge '5.0.0' }
        return ($mods -and $mods.Count -gt 0)
      }
    }
  }

  

  Context 'When Pester v5+ present' {
    It 'returns $true' {
      Invoke-WithFunctionShadow -Name Get-Module -Definition {
        param([switch]$ListAvailable,[string]$Name)
        if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'5.7.1' } }
        Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
      } -Body {
        Test-PesterAvailable | Should -BeTrue
      }
    }
  }

  Context 'When only older Pester present' {
    It 'returns $false' {
      Invoke-WithFunctionShadow -Name Get-Module -Definition {
        param([switch]$ListAvailable,[string]$Name)
        if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'4.10.1' } }
        Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
      } -Body {
        Test-PesterAvailable | Should -BeFalse
      }
    }
  }

  Context 'When Pester absent' {
    It 'returns $false' {
      Invoke-WithFunctionShadow -Name Get-Module -Definition {
        param([switch]$ListAvailable,[string]$Name)
        if ($ListAvailable -and $Name -eq 'Pester') { return @() }
        Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
      } -Body {
        Test-PesterAvailable | Should -BeFalse
      }
    }
  }
}
