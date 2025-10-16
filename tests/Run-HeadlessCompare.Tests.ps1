Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe "Run-HeadlessCompare.ps1" -Tag "Unit" {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $scriptPath = Join-Path $repoRoot "tools" "Run-HeadlessCompare.ps1"
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
      throw "Run-HeadlessCompare.ps1 not found at $scriptPath"
    }
    $script:RunHeadlessScript = $scriptPath
  }

  It "defaults to cli-only policy, skips warmup, and forwards timeout" {
    $work = Join-Path $TestDrive "headless-default"
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    $fsRoot = (Resolve-Path ".").Path
    try {
      New-Item -ItemType Directory -Path "tools" | Out-Null
      Copy-Item -LiteralPath $script:RunHeadlessScript -Destination "tools/Run-HeadlessCompare.ps1"

      $logPath = Join-Path $fsRoot "invoke-log.json"
      $stubLines = @(
        "param(",
        "  [string]`$BaseVi,",
        "  [string]`$HeadVi,",
        "  [Alias('LabVIEWPath')][string]`$LabVIEWExePath,",
        "  [Alias('LVCompareExePath')][string]`$LVComparePath,",
        "  [string]`$OutputRoot,",
        "  [ValidateSet('detect','spawn','skip')][string]`$Warmup,",
        "  [switch]`$RenderReport,",
        "  [switch]`$CloseLabVIEW,",
        "  [switch]`$CloseLVCompare,",
        "  [int]`$TimeoutSeconds,",
        "  [switch]`$DisableTimeout",
        ")",
        "`$logDir = Split-Path '$logPath'",
        "if (`$logDir -and -not (Test-Path `$logDir)) { New-Item -ItemType Directory -Path `$logDir -Force | Out-Null }",
        "`$payload = [ordered]@{",
        "  base = `$BaseVi",
        "  head = `$HeadVi",
        "  output = `$OutputRoot",
        "  warmup = `$Warmup",
        "  renderReport = `$RenderReport.IsPresent",
        "  closeLabVIEW = `$CloseLabVIEW.IsPresent",
        "  closeLVCompare = `$CloseLVCompare.IsPresent",
        "  timeout = `$TimeoutSeconds",
        "  disableTimeout = `$DisableTimeout.IsPresent",
        "  policy = [System.Environment]::GetEnvironmentVariable('LVCI_COMPARE_POLICY')",
        "  mode = [System.Environment]::GetEnvironmentVariable('LVCI_COMPARE_MODE')",
        "}",
        "`$payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath '$logPath' -Encoding utf8",
        "exit 0"
      )
      $stubPath = [System.IO.Path]::Combine($fsRoot, "tools", "TestStand-CompareHarness.ps1")
      [System.IO.File]::WriteAllLines($stubPath, $stubLines)
      Test-Path -LiteralPath $stubPath | Should -BeTrue

      $baseFs = Join-Path $fsRoot "VI-Base.vi"
      $headFs = Join-Path $fsRoot "VI-Head.vi"
      Set-Content -LiteralPath $baseFs -Value "base" -Encoding UTF8
      Set-Content -LiteralPath $headFs -Value "head" -Encoding UTF8

      Remove-Item Env:LVCI_COMPARE_POLICY, Env:LVCI_COMPARE_MODE -ErrorAction SilentlyContinue

      $output = & pwsh -NoLogo -NoProfile -File "tools/Run-HeadlessCompare.ps1" `
        -BaseVi $baseFs `
        -HeadVi $headFs `
        -OutputRoot (Join-Path $fsRoot "results") 2>&1
      $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")

      Test-Path -LiteralPath $logPath | Should -BeTrue
      $data = Get-Content -LiteralPath $logPath -Raw | ConvertFrom-Json
      $data.policy | Should -Be "cli-only"
      $data.mode | Should -Be "labview-cli"
      $data.warmup | Should -Be "skip"
      $data.timeout | Should -Be 600
      $data.disableTimeout | Should -BeFalse
      $data.closeLabVIEW | Should -BeTrue
      $data.closeLVCompare | Should -BeTrue
    }
    finally {
      Pop-Location
    }
  }

  It "honours WarmupMode, DisableTimeout, and DisableCleanup options" {
    $work = Join-Path $TestDrive "headless-options"
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    $fsRoot = (Resolve-Path ".").Path
    try {
      New-Item -ItemType Directory -Path "tools" | Out-Null
      Copy-Item -LiteralPath $script:RunHeadlessScript -Destination "tools/Run-HeadlessCompare.ps1"

      $logPath = Join-Path $fsRoot "invoke-log.json"
      $stubLines = @(
        "param(",
        "  [string]`$BaseVi,",
        "  [string]`$HeadVi,",
        "  [Alias('LabVIEWPath')][string]`$LabVIEWExePath,",
        "  [Alias('LVCompareExePath')][string]`$LVComparePath,",
        "  [string]`$OutputRoot,",
        "  [ValidateSet('detect','spawn','skip')][string]`$Warmup,",
        "  [switch]`$RenderReport,",
        "  [switch]`$CloseLabVIEW,",
        "  [switch]`$CloseLVCompare,",
        "  [int]`$TimeoutSeconds,",
        "  [switch]`$DisableTimeout",
        ")",
        "`$logDir = Split-Path '$logPath'",
        "if (`$logDir -and -not (Test-Path `$logDir)) { New-Item -ItemType Directory -Path `$logDir -Force | Out-Null }",
        "`$payload = [ordered]@{",
        "  warmup = `$Warmup",
        "  renderReport = `$RenderReport.IsPresent",
        "  closeLabVIEW = `$CloseLabVIEW.IsPresent",
        "  closeLVCompare = `$CloseLVCompare.IsPresent",
        "  timeout = `$TimeoutSeconds",
        "  disableTimeout = `$DisableTimeout.IsPresent",
        "  policy = [System.Environment]::GetEnvironmentVariable('LVCI_COMPARE_POLICY')",
        "  mode = [System.Environment]::GetEnvironmentVariable('LVCI_COMPARE_MODE')",
        "}",
        "`$payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath '$logPath' -Encoding utf8",
        "exit 0"
      )
      $stubPath = [System.IO.Path]::Combine($fsRoot, "tools", "TestStand-CompareHarness.ps1")
      [System.IO.File]::WriteAllLines($stubPath, $stubLines)
      Test-Path -LiteralPath $stubPath | Should -BeTrue

      $baseFs = Join-Path $fsRoot "Base.vi"
      $headFs = Join-Path $fsRoot "Head.vi"
      Set-Content -LiteralPath $baseFs -Value "base" -Encoding UTF8
      Set-Content -LiteralPath $headFs -Value "head" -Encoding UTF8

      $env:LVCI_COMPARE_POLICY = "cli-first"
      $env:LVCI_COMPARE_MODE = "labview-cli"

      $output = & pwsh -NoLogo -NoProfile -File "tools/Run-HeadlessCompare.ps1" `
        -BaseVi $baseFs `
        -HeadVi $headFs `
        -OutputRoot (Join-Path $fsRoot "results") `
        -WarmupMode detect `
        -RenderReport `
        -TimeoutSeconds 45 `
        -DisableTimeout `
        -DisableCleanup 2>&1
      $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")

      Test-Path -LiteralPath $logPath | Should -BeTrue
      $data = Get-Content -LiteralPath $logPath -Raw | ConvertFrom-Json
      $data.policy | Should -Be "cli-first"
      $data.mode | Should -Be "labview-cli"
      $data.warmup | Should -Be "detect"
      $data.renderReport | Should -BeTrue
      $data.timeout | Should -Be 45
      $data.disableTimeout | Should -BeTrue
      $data.closeLabVIEW | Should -BeFalse
      $data.closeLVCompare | Should -BeFalse
    }
    finally {
      Remove-Item Env:LVCI_COMPARE_POLICY, Env:LVCI_COMPARE_MODE -ErrorAction SilentlyContinue
      Pop-Location
    }
  }
}
