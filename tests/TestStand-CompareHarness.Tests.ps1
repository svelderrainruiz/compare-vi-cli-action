Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'TestStand-CompareHarness.ps1 (VI2 baseline pair)' -Tag 'Unit' {
  It 'passes repo VI2 artefacts to Invoke-LVCompare' {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $baseReal = Join-Path $repoRoot 'VI2.vi'
    $headReal = Join-Path $repoRoot 'tmp-commit-236ffab\VI2.vi'
    if (-not (Test-Path -LiteralPath $baseReal -PathType Leaf) -or -not (Test-Path -LiteralPath $headReal -PathType Leaf)) {
      Set-ItResult -Skipped -Because 'Required VI fixtures not present'
      return
    }

    $work = Join-Path $TestDrive 'harness-vi2-specific'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      New-Item -ItemType Directory -Path 'tools' | Out-Null
      Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\TestStand-CompareHarness.ps1') -Destination 'tools\TestStand-CompareHarness.ps1'

      Set-Content -LiteralPath 'tools/Warmup-LabVIEWRuntime.ps1' -Encoding UTF8 -Value @'
param(
  [string]$LabVIEWPath,
  [string]$JsonLogPath
)
if ($JsonLogPath) {
  $dir = Split-Path -Parent $JsonLogPath
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  '{"type":"warmup","schema":"stub"}' | Set-Content -LiteralPath $JsonLogPath -Encoding utf8
}
exit 0
'@

      $invokeStub = @'
param(
  [string]$BaseVi,
  [string]$HeadVi,
  [Alias('LabVIEWPath')]
  [string]$LabVIEWExePath,
  [Alias('LVCompareExePath')]
  [string]$LVComparePath,
  [string]$OutputDir,
  [switch]$RenderReport,
  [string]$JsonLogPath,
  [object]$Flags
)
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$argsArray = @()
if ($Flags -is [System.Array]) { $argsArray = @($Flags) }
elseif ($Flags) { $argsArray = @([string]$Flags) }
$log = [pscustomobject]@{
  base = $BaseVi
  head = $HeadVi
  lvExe = $LabVIEWExePath
  lvCompare = $LVComparePath
}
$log | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'invoke-args.json') -Encoding utf8
exit 0
'@
      Set-Content -LiteralPath 'tools/Invoke-LVCompare.ps1' -Value $invokeStub -Encoding UTF8

      Set-Content -LiteralPath 'tools/Close-LVCompare.ps1' -Value "param() exit 0" -Encoding UTF8
      Set-Content -LiteralPath 'tools/Close-LabVIEW.ps1' -Value "param() exit 0" -Encoding UTF8

      $outputRoot = Join-Path $work 'results'
      $harness = Join-Path $work 'tools\TestStand-CompareHarness.ps1'
      & pwsh -NoLogo -NoProfile -File $harness `
        -BaseVi $baseReal `
        -HeadVi $headReal `
        -LabVIEWPath 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe' `
        -OutputRoot $outputRoot `
        -Warmup skip `
        -RenderReport:$false `
        -CloseLabVIEW `
        -CloseLVCompare *> $null

      $invokeLogPath = Get-ChildItem -Path $outputRoot -Recurse -Filter 'invoke-args.json' | Select-Object -First 1
      $invokeLogPath | Should -Not -BeNullOrEmpty
      $invokeData = Get-Content -LiteralPath $invokeLogPath.FullName -Raw | ConvertFrom-Json
      $invokeData.base | Should -Be $baseReal
      $invokeData.head | Should -Be $headReal
      $invokeData.lvExe | Should -Be 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe'
      $invokeData.lvCompare | Should -BeNullOrEmpty
    }
    finally { Pop-Location }
  }
}
