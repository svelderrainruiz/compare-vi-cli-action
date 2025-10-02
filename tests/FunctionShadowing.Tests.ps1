# Tests for Invoke-WithFunctionShadow helper

Describe 'Inline Function Shadowing (Pester probe simulation)' -Tag 'Unit' {
  BeforeAll {}

  It 'simulates Pester old version (returns false for probe)' {
    function Get-Module { param([switch]$ListAvailable,[string]$Name)
      if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'4.10.1' } }
      Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
    }
    if (-not (Get-Command Test-PesterAvailable -ErrorAction SilentlyContinue)) {
      function Test-PesterAvailable { @(Get-Module -ListAvailable -Name Pester | Where-Object { $_ -and $_.Version -ge '5.0.0' }).Count -gt 0 }
    }
    Test-PesterAvailable | Should -BeFalse
    Remove-Item Function:Get-Module -ErrorAction SilentlyContinue
  }

  It 'simulates Pester new version (returns true for probe)' {
    function Get-Module { param([switch]$ListAvailable,[string]$Name)
      if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'5.7.1' } }
      Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
    }
    if (-not (Get-Command Test-PesterAvailable -ErrorAction SilentlyContinue)) {
      function Test-PesterAvailable { @(Get-Module -ListAvailable -Name Pester | Where-Object { $_ -and $_.Version -ge '5.0.0' }).Count -gt 0 }
    }
    Test-PesterAvailable | Should -BeTrue
    Remove-Item Function:Get-Module -ErrorAction SilentlyContinue
  }

}
