Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Verify-LocalDiffSession.ps1' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:toolPath = Join-Path $repoRoot 'tools' 'Verify-LocalDiffSession.ps1'
    Test-Path -LiteralPath $script:toolPath | Should -BeTrue
  }

  It 'produces a summary for normal mode using the stub' {
    $work = Join-Path $TestDrive 'lds-normal'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -UseStub -ResultsRoot $resultsDir -Mode 'normal'

    $result | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $result.resultsDir -PathType Container | Should -BeTrue
    Test-Path -LiteralPath $result.summary -PathType Leaf | Should -BeTrue

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.mode | Should -Be 'normal'
    $summary.runs.Count | Should -Be 1
    $summary.runs[0].cliSkipped | Should -BeFalse
    ($summary.runs[0].skipReason -eq $null -or [string]::IsNullOrWhiteSpace($summary.runs[0].skipReason)) | Should -BeTrue
    if ($summary.runs[0].stdoutPath) {
      Test-Path -LiteralPath $summary.runs[0].stdoutPath -PathType Leaf | Should -BeTrue
      (Get-Content -LiteralPath $summary.runs[0].stdoutPath -Raw) | Should -Match 'Stub LVCompare run'
    }
  }

  It 'suppresses CLI in cli-suppressed mode' {
    $work = Join-Path $TestDrive 'lds-suppress'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -ResultsRoot $resultsDir -Mode 'cli-suppressed'

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.runs.Count | Should -Be 1
    $summary.runs[0].cliSkipped | Should -BeTrue
    $summary.runs[0].skipReason | Should -Be 'COMPAREVI_NO_CLI_CAPTURE'
  }

  It 'records sentinel skip on duplicate-window mode' {
    $work = Join-Path $TestDrive 'lds-dup'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -UseStub -ResultsRoot $resultsDir -Mode 'duplicate-window' -SentinelTtlSeconds 5

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.runs.Count | Should -Be 2
    $summary.runs[0].cliSkipped | Should -BeFalse
    $summary.runs[1].cliSkipped | Should -BeTrue
    $summary.runs[1].skipReason | Should -Match '^sentinel:'
  }

  It 'suppresses CLI in git-context mode' {
    $work = Join-Path $TestDrive 'lds-git-context'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $result = & $script:toolPath -BaseVi $base -HeadVi $head -UseStub -ResultsRoot $resultsDir -Mode 'git-context'

    $summary = Get-Content -LiteralPath $result.summary -Raw | ConvertFrom-Json
    $summary.runs.Count | Should -Be 1
    $summary.runs[0].cliSkipped | Should -BeTrue
    $summary.runs[0].skipReason | Should -Be 'git-context'
  }

  It 'reports setup status when LVCompare probe fails' {
    $work = Join-Path $TestDrive 'lds-setup'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
    $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
    $resultsDir = Join-Path $work 'results'

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $localConfigPath = Join-Path $repoRoot 'configs/labview-paths.local.json'
    $primaryConfigPath = Join-Path $repoRoot 'configs/labview-paths.json'
    $localBackup = Join-Path $TestDrive 'labview-paths.local.json.bak'
    $primaryBackup = Join-Path $TestDrive 'labview-paths.json.bak'

    if (Test-Path -LiteralPath $localConfigPath -PathType Leaf) {
      Move-Item -LiteralPath $localConfigPath -Destination $localBackup -Force
    }
    if (Test-Path -LiteralPath $primaryConfigPath -PathType Leaf) {
      Move-Item -LiteralPath $primaryConfigPath -Destination $primaryBackup -Force
    }

    try {
      $result = & $script:toolPath -BaseVi $base -HeadVi $head -ResultsRoot $resultsDir -Mode 'normal' -ProbeSetup

      $result.runs.Count | Should -Be 0
      $result.setupStatus.ok | Should -BeFalse
      $result.setupStatus.message | Should -Match 'exited with code'
    } finally {
      if (Test-Path -LiteralPath $localBackup -PathType Leaf) {
        Move-Item -LiteralPath $localBackup -Destination $localConfigPath -Force
      }
      if (Test-Path -LiteralPath $primaryBackup -PathType Leaf) {
        Move-Item -LiteralPath $primaryBackup -Destination $primaryConfigPath -Force
      }
    }

  }

  It 'removes generated config when -Stateless' {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $localConfigPath = Join-Path $repoRoot 'configs/labview-paths.local.json'
    $backupPath = Join-Path $TestDrive 'labview-paths.local.json.bak'
    if (Test-Path -LiteralPath $localConfigPath -PathType Leaf) {
      Move-Item -LiteralPath $localConfigPath -Destination $backupPath -Force
    }

    try {
      Set-Content -LiteralPath $localConfigPath -Value '{}' -Encoding utf8

      $work = Join-Path $TestDrive 'lds-stateless'
      New-Item -ItemType Directory -Path $work | Out-Null
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Value '' -Encoding ascii
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Value '' -Encoding ascii
      $resultsDir = Join-Path $work 'results'

      & $script:toolPath -BaseVi $base -HeadVi $head -ResultsRoot $resultsDir -Mode 'normal' -UseStub -Stateless -LabVIEWVersion '2025' -LabVIEWBitness '64' | Out-Null

      Test-Path -LiteralPath $localConfigPath -PathType Leaf | Should -BeFalse
    } finally {
      if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Move-Item -LiteralPath $backupPath -Destination $localConfigPath -Force
      } elseif (Test-Path -LiteralPath $localConfigPath -PathType Leaf) {
        Remove-Item -LiteralPath $localConfigPath -Force
      }
    }
  }
}
