Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'LabVIEW CLI duplicate suppression' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:driverPath = Join-Path $repoRoot 'tools' 'Invoke-LVCompare.ps1'
    Test-Path -LiteralPath $script:driverPath | Should -BeTrue
  }

  It 'suppresses CLI when COMPAREVI_NO_CLI_CAPTURE is set' {
    $work = Join-Path $TestDrive 'cli-suppress-env'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
      $outDir = Join-Path $work 'out'

      $prevNoCli = $env:COMPAREVI_NO_CLI_CAPTURE
      try {
        $env:COMPAREVI_NO_CLI_CAPTURE = '1'
        & $script:driverPath -BaseVi $base -HeadVi $head -OutputDir $outDir -Quiet *> $null
      } finally {
        if ($null -eq $prevNoCli) { Remove-Item Env:COMPAREVI_NO_CLI_CAPTURE -ErrorAction SilentlyContinue } else { $env:COMPAREVI_NO_CLI_CAPTURE = $prevNoCli }
      }

      $capPath = Join-Path $outDir 'lvcompare-capture.json'
      Test-Path -LiteralPath $capPath | Should -BeTrue
      $cap = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json
      $cap.environment | Should -Not -BeNullOrEmpty
      $cap.environment.cli | Should -Not -BeNullOrEmpty
      $cap.environment.cli.skipped | Should -BeTrue
      $cap.environment.cli.skipReason | Should -Be 'COMPAREVI_NO_CLI_CAPTURE'
    }
    finally { Pop-Location }
  }

  It 'suppresses CLI in Git context when COMPAREVI_SUPPRESS_CLI_IN_GIT is set' {
    $work = Join-Path $TestDrive 'cli-suppress-git'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
      $outDir = Join-Path $work 'out'

      $prevSuppress = $env:COMPAREVI_SUPPRESS_CLI_IN_GIT
      $prevGitDir   = $env:GIT_DIR
      try {
        $env:COMPAREVI_SUPPRESS_CLI_IN_GIT = '1'
        $env:GIT_DIR = '.'
        & $script:driverPath -BaseVi $base -HeadVi $head -OutputDir $outDir -Quiet *> $null
      } finally {
        if ($null -eq $prevSuppress) { Remove-Item Env:COMPAREVI_SUPPRESS_CLI_IN_GIT -ErrorAction SilentlyContinue } else { $env:COMPAREVI_SUPPRESS_CLI_IN_GIT = $prevSuppress }
        if ($null -eq $prevGitDir) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue } else { $env:GIT_DIR = $prevGitDir }
      }

      $capPath = Join-Path $outDir 'lvcompare-capture.json'
      Test-Path -LiteralPath $capPath | Should -BeTrue
      $cap = Get-Content -LiteralPath $capPath -Raw | ConvertFrom-Json
      $cap.environment | Should -Not -BeNullOrEmpty
      $cap.environment.cli | Should -Not -BeNullOrEmpty
      $cap.environment.cli.skipped | Should -BeTrue
      $cap.environment.cli.skipReason | Should -Be 'git-context'
    }
    finally { Pop-Location }
  }
}
