# Regression test: Ensure Invoke-WithFunctionShadow works across a nested dispatcher invocation
# This guards against future changes that might reintroduce mock/command scope issues when the
# dispatcher launches an inner Pester run.

Describe 'Inline Shadowing (Nested Dispatcher)' -Tag 'Unit' {
  BeforeAll {
    if (-not (Get-Command Test-PesterAvailable -ErrorAction SilentlyContinue)) {
      function Test-PesterAvailable {
        $mods = @(Get-Module -ListAvailable -Name Pester | Where-Object { $_ -and $_.Version -ge '5.0.0' })
        return ($mods.Count -gt 0)
      }
    }
  }

  It 'retains shadow effectiveness before and after nested dispatcher run' {
    # 1. Simulate older Pester (probe should be false)
    function Get-Module { param([switch]$ListAvailable,[string]$Name)
      if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'4.10.1' } }
      Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
    }
    Test-PesterAvailable | Should -BeFalse
    Remove-Item Function:Get-Module -ErrorAction SilentlyContinue

    # 2. Nested dispatcher run in isolated workspace
    $workspace = Join-Path $TestDrive 'shadow-nested'
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null
    $testsDir = Join-Path $workspace 'tests'
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

    $innerTest = Join-Path $testsDir 'Inner.Tests.ps1'
@'
Describe "Inner Smoke" {
  It "passes" { 1 | Should -Be 1 }
}
'@ | Set-Content -Path $innerTest

    $dispatcherCopy = Join-Path $workspace 'Invoke-PesterTests.ps1'
    Copy-Item -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-PesterTests.ps1') -Destination $dispatcherCopy

    Push-Location $workspace
    try {
      $null = & $dispatcherCopy -TestsPath 'tests' -IncludeIntegration 'false' -ResultsPath 'results' 2>&1
      $LASTEXITCODE | Should -Be 0
    } finally {
      Pop-Location
    }

    # 3. Simulate new Pester (probe should be true)
    function Get-Module { param([switch]$ListAvailable,[string]$Name)
      if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'5.7.1' } }
      Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
    }
    Test-PesterAvailable | Should -BeTrue
    Remove-Item Function:Get-Module -ErrorAction SilentlyContinue
  }
}
