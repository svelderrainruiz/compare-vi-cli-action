Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'VendorTools LabVIEW helpers' {
  BeforeAll {
    $script:repoRoot = (git rev-parse --show-toplevel).Trim()
    $script:modulePath = Join-Path $script:repoRoot 'tools/VendorTools.psm1'
    Import-Module $script:modulePath -Force

    $script:localConfigPath = Join-Path $script:repoRoot 'configs/labview-paths.local.json'
    $script:hadExistingLocalConfig = Test-Path -LiteralPath $script:localConfigPath -PathType Leaf
    if ($script:hadExistingLocalConfig) {
      $script:existingLocalConfig = Get-Content -LiteralPath $script:localConfigPath -Raw
    } else {
      $script:existingLocalConfig = $null
    }
  }

  AfterEach {
    if ($script:localConfigPath -and (Test-Path -LiteralPath $script:localConfigPath -PathType Leaf)) {
      Remove-Item -LiteralPath $script:localConfigPath -Force
    }
  }

  AfterAll {
    if ($script:hadExistingLocalConfig) {
      Set-Content -LiteralPath $script:localConfigPath -Value $script:existingLocalConfig -Encoding utf8
    } else {
      if ($script:localConfigPath -and (Test-Path -LiteralPath $script:localConfigPath -PathType Leaf)) {
        Remove-Item -LiteralPath $script:localConfigPath -Force
      }
    }
  }

  It 'resolves LabVIEW executables and ini values from local config' {
    $tempRoot = Join-Path $TestDrive 'labview-local'
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    $fakeExe = Join-Path $tempRoot 'LabVIEW.exe'
    [System.IO.File]::WriteAllBytes($fakeExe, [byte[]](0x00)) | Out-Null
    $fakeIni = Join-Path $tempRoot 'LabVIEW.ini'
    Set-Content -LiteralPath $fakeIni -Value "SCCUseInLabVIEW=True`nSCCProviderIsActive=False`n"

    @"
{
  "labview": [ "$fakeExe" ]
}
"@ | Set-Content -LiteralPath $script:localConfigPath

    $candidates = Get-LabVIEWCandidateExePaths -LabVIEWExePath $fakeExe
    $resolvedExe = (Resolve-Path -LiteralPath $fakeExe).Path
    $candidates | Should -Contain $resolvedExe

    $iniPath = Get-LabVIEWIniPath -LabVIEWExePath $fakeExe
    $iniPath | Should -Be (Resolve-Path -LiteralPath $fakeIni).Path

    $sccValue = Get-LabVIEWIniValue -LabVIEWExePath $fakeExe -Key 'SCCUseInLabVIEW'
    $sccValue | Should -Be 'True'
  }

  It 'includes version-scoped executables when present' {
    $tempRoot = Join-Path $TestDrive 'labview-version'
    New-Item -ItemType Directory -Path $tempRoot | Out-Null

    $versionExe = Join-Path $tempRoot 'Program Files\NI\LabVIEW 2025\LabVIEW.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $versionExe) -Force | Out-Null
    Set-Content -LiteralPath $versionExe -Value '' -Encoding ascii

    $configJson = @{
      versions = @{
        '2025' = @{
          '64' = @{
            LabVIEWExePath = $versionExe
          }
        }
      }
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $script:localConfigPath -Value $configJson -Encoding utf8

    $candidates = Get-LabVIEWCandidateExePaths
    $resolvedVersionExe = (Resolve-Path -LiteralPath $versionExe).Path
    $candidates | Should -Contain $resolvedVersionExe
  }
}
