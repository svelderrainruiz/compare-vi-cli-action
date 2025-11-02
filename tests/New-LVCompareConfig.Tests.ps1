Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'New-LVCompareConfig.ps1' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:toolPath = Join-Path $repoRoot 'tools' 'New-LVCompareConfig.ps1'
    Test-Path -LiteralPath $script:toolPath | Should -BeTrue
  }

  It 'writes config with supplied paths (non-interactive)' {
    $work = Join-Path $TestDrive 'config-basic'
    New-Item -ItemType Directory -Path $work | Out-Null

    $labviewExe = Join-Path $work 'LabVIEW.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $labviewExe) -Force | Out-Null
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii

    $lvcompareExe = Join-Path $work 'LVCompare.exe'
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii

    $cliExe = Join-Path $work 'LabVIEWCLI.exe'
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    $outputPath = Join-Path $work 'labview-paths.json'
    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -NonInteractive | Out-Null

    $config = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 8
    $resolvedExe = (Resolve-Path -LiteralPath $labviewExe).Path
    $resolvedCompare = (Resolve-Path -LiteralPath $lvcompareExe).Path
    $resolvedCli = (Resolve-Path -LiteralPath $cliExe).Path

    $config.LabVIEWExePath | Should -Be $resolvedExe
    $config.LVComparePath | Should -Be $resolvedCompare
    $config.LabVIEWCLIPath | Should -Be $resolvedCli
    $config.labview[0] | Should -Be $resolvedExe
    $config.lvcompare[0] | Should -Be $resolvedCompare
    $config.labviewcli[0] | Should -Be $resolvedCli
    $config.PSObject.Properties['versions'] | Should -Be $null
  }

  It 'overwrites existing file when -Force' {
    $work = Join-Path $TestDrive 'config-force'
    New-Item -ItemType Directory -Path $work | Out-Null
    $outputPath = Join-Path $work 'labview-paths.json'
    Set-Content -LiteralPath $outputPath -Value '{}' -Encoding utf8

    $labviewExe = Join-Path $work 'LabVIEW.exe'
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii
    $lvcompareExe = Join-Path $work 'LVCompare.exe'
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii
    $cliExe = Join-Path $work 'LabVIEWCLI.exe'
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -NonInteractive -Force | Out-Null

    $config = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 8
    $config.LVComparePath | Should -Be (Resolve-Path -LiteralPath $lvcompareExe).Path
  }

  It 'creates parent directory when needed' {
    $nestedRoot = Join-Path $TestDrive 'config-nested'
    $outputPath = Join-Path $nestedRoot 'configs' 'labview-paths.json'
    $labviewExe = Join-Path $TestDrive 'LabVIEW.exe'
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii
    $lvcompareExe = Join-Path $TestDrive 'LVCompare.exe'
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii
    $cliExe = Join-Path $TestDrive 'LabVIEWCLI.exe'
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -NonInteractive -Force | Out-Null

    $parentDir = Split-Path -Parent $outputPath
    Test-Path -LiteralPath $parentDir -PathType Container | Should -BeTrue
    Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
  }

  It 'records version-specific entry when version provided' {
    $work = Join-Path $TestDrive 'config-version-explicit'
    New-Item -ItemType Directory -Path $work | Out-Null

    $labviewExe = Join-Path $work 'Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $labviewExe) -Force | Out-Null
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii

    $lvcompareExe = Join-Path $work 'Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $lvcompareExe) -Force | Out-Null
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii

    $cliExe = Join-Path $work 'Program Files\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cliExe) -Force | Out-Null
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    $outputPath = Join-Path $work 'labview-paths.json'
    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -Version '2025' -Bitness '64' -NonInteractive | Out-Null

    $config = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 8
    $versionNode = $config.versions.'2025'.'64'
    $versionNode | Should -Not -BeNullOrEmpty
    $versionNode.LabVIEWExePath | Should -Be (Resolve-Path -LiteralPath $labviewExe).Path
    $versionNode.LVComparePath | Should -Be (Resolve-Path -LiteralPath $lvcompareExe).Path
    $versionNode.LabVIEWCLIPath | Should -Be (Resolve-Path -LiteralPath $cliExe).Path
  }

  It 'merges new version entry when existing config present' {
    $work = Join-Path $TestDrive 'config-version-merge'
    New-Item -ItemType Directory -Path $work | Out-Null
    $outputPath = Join-Path $work 'labview-paths.json'

    $existingConfig = @{
      LabVIEWExePath = 'C:\Existing\LabVIEW.exe'
      versions       = @{
        '2023' = @{
          '64' = @{
            LabVIEWExePath = 'C:\Existing\LabVIEW.exe'
          }
        }
      }
    } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $outputPath -Value $existingConfig -Encoding utf8

    $labviewExe = Join-Path $work 'Program Files\National Instruments\LabVIEW 2024\LabVIEW.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $labviewExe) -Force | Out-Null
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii

    $lvcompareExe = Join-Path $work 'Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $lvcompareExe) -Force | Out-Null
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii

    $cliExe = Join-Path $work 'Program Files\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cliExe) -Force | Out-Null
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -Version '2024' -Bitness '64' -NonInteractive -Force | Out-Null

    $config = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 8
    $config.versions.'2023'.'64'.LabVIEWExePath | Should -Be 'C:\Existing\LabVIEW.exe'
    $config.versions.'2024'.'64'.LabVIEWExePath | Should -Be (Resolve-Path -LiteralPath $labviewExe).Path
  }

  It 'auto-detects version metadata from LabVIEW path' {
    $work = Join-Path $TestDrive 'config-version-auto'
    New-Item -ItemType Directory -Path $work | Out-Null

    $labviewExe = Join-Path $work 'Program Files (x86)\National Instruments\LabVIEW 2024 (32-bit)\LabVIEW.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $labviewExe) -Force | Out-Null
    Set-Content -LiteralPath $labviewExe -Value '' -Encoding ascii

    $lvcompareExe = Join-Path $work 'Program Files (x86)\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $lvcompareExe) -Force | Out-Null
    Set-Content -LiteralPath $lvcompareExe -Value '' -Encoding ascii

    $cliExe = Join-Path $work 'Program Files (x86)\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cliExe) -Force | Out-Null
    Set-Content -LiteralPath $cliExe -Value '' -Encoding ascii

    $outputPath = Join-Path $work 'labview-paths.json'
    & $script:toolPath -OutputPath $outputPath -LabVIEWExePath $labviewExe -LVComparePath $lvcompareExe -LabVIEWCLIPath $cliExe -NonInteractive | Out-Null

    $config = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 8
    $config.versions.'2024'.'32'.LabVIEWExePath | Should -Be (Resolve-Path -LiteralPath $labviewExe).Path
    $config.versions.'2024'.'32'.LVComparePath | Should -Be (Resolve-Path -LiteralPath $lvcompareExe).Path
    $config.versions.'2024'.'32'.LabVIEWCLIPath | Should -Be (Resolve-Path -LiteralPath $cliExe).Path
  }
}
