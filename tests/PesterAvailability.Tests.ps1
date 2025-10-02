# Tests for Test-PesterAvailable probe function
# These are pure unit tests that mock Get-Module to validate the probe logic.

Describe 'Test-PesterAvailable' -Tag 'Unit' {
  BeforeAll {
    # Ensure function is available (loaded from existing tests file or re-define minimal shim if absent)
    if (-not (Get-Command Test-PesterAvailable -ErrorAction SilentlyContinue)) {
      function Test-PesterAvailable {
        $mods = Get-Module -ListAvailable -Name Pester | Where-Object { $_ -and $_.Version -ge '5.0.0' }
        return ($mods -and $mods.Count -gt 0)
      }
    }
  }

  Context 'When Pester v5+ present' {
    BeforeEach {
      Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' } -MockWith {
        [pscustomobject]@{ Name='Pester'; Version=[version]'5.7.1' }
      }
    }
    It 'returns $true' {
      Test-PesterAvailable | Should -BeTrue
    }
  }

  Context 'When only older Pester present' {
    BeforeEach {
      Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' } -MockWith {
        [pscustomobject]@{ Name='Pester'; Version=[version]'4.10.1' }
      }
    }
    It 'returns $false' {
      Test-PesterAvailable | Should -BeFalse
    }
  }

  Context 'When Pester absent' {
    BeforeEach {
      Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' } -MockWith { @() }
    }
    It 'returns $false' {
      Test-PesterAvailable | Should -BeFalse
    }
  }
}
