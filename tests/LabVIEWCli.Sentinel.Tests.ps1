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

      $driverQuoted = $script:driverPath.Replace("'", "''")
      $baseQuoted = $base.Replace("'", "''")
      $headQuoted = $head.Replace("'", "''")
      $outQuoted = $outDir.Replace("'", "''")
      $command = "& { \$env:COMPAREVI_NO_CLI_CAPTURE='1'; & '$driverQuoted' -BaseVi '$baseQuoted' -HeadVi '$headQuoted' -OutputDir '$outQuoted' -Quiet; exit `$LASTEXITCODE }"
      & pwsh -NoLogo -NoProfile -Command $command *> $null

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

      $driverQuoted = $script:driverPath.Replace("'", "''")
      $baseQuoted = $base.Replace("'", "''")
      $headQuoted = $head.Replace("'", "''")
      $outQuoted = $outDir.Replace("'", "''")
      $command = "& { \$env:COMPAREVI_SUPPRESS_CLI_IN_GIT='1'; \$env:GIT_DIR='.'; & '$driverQuoted' -BaseVi '$baseQuoted' -HeadVi '$headQuoted' -OutputDir '$outQuoted' -Quiet; exit `$LASTEXITCODE }"
      & pwsh -NoLogo -NoProfile -Command $command *> $null

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

