$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Describe 'Invoke-VIDiffSweepStrong.ps1' -Tag 'Script','IconEditor' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:strongSweepPath = Join-Path $repoRoot 'tools' 'icon-editor' 'Invoke-VIDiffSweepStrong.ps1'
    Test-Path -LiteralPath $script:strongSweepPath | Should -BeTrue
    $script:weakSweepPath = Join-Path $repoRoot 'tools' 'icon-editor' 'Invoke-VIDiffSweep.ps1'
    Test-Path -LiteralPath $script:weakSweepPath | Should -BeTrue
  }

  It 'skips pure renames without launching compares when run in DryRun mode' {
    $repoPath = Join-Path $TestDrive 'icon-editor-strong-rename'
    git init $repoPath | Out-Null
    Push-Location $repoPath
    try {
      git config user.email 'tester@example.com' | Out-Null
      git config user.name 'Tester' | Out-Null

      New-Item -ItemType Directory -Path 'resource/plugins' -Force | Out-Null
      Set-Content -LiteralPath 'resource/plugins/Original.vi' -Value 'initial content' -Encoding utf8
      git add . | Out-Null
      git commit -m 'initial commit' | Out-Null

      git mv 'resource/plugins/Original.vi' 'resource/plugins/Renamed.vi' | Out-Null
      git commit -m 'rename keeping content' | Out-Null

      $result = & $script:strongSweepPath `
        -RepoPath $repoPath `
        -BaseRef 'HEAD~1' `
        -HeadRef 'HEAD' `
        -DryRun `
        -Quiet

      $result.totalCommits | Should -Be 1
      $result.candidates.totalCommits | Should -Be 1
      $commit = $result.commits[0]
      $commit.comparePaths.Count | Should -Be 0
      $commit.skipped.Count | Should -Be 1
      $commit.skipped[0].reason | Should -Match 'rename'
    }
    finally {
      Pop-Location
    }
  }

  It 'selects VI files with content changes for comparison decisions' {
    $repoPath = Join-Path $TestDrive 'icon-editor-strong-modify'
    git init $repoPath | Out-Null
    Push-Location $repoPath
    try {
      git config user.email 'tester@example.com' | Out-Null
      git config user.name 'Tester' | Out-Null

      New-Item -ItemType Directory -Path 'resource/plugins' -Force | Out-Null
      Set-Content -LiteralPath 'resource/plugins/Sample.vi' -Value 'first version' -Encoding utf8
      git add . | Out-Null
      git commit -m 'initial commit' | Out-Null

      Set-Content -LiteralPath 'resource/plugins/Sample.vi' -Value 'updated version' -Encoding utf8
      git commit -am 'modify sample' | Out-Null

      $result = & $script:strongSweepPath `
        -RepoPath $repoPath `
        -BaseRef 'HEAD~1' `
        -HeadRef 'HEAD' `
        -DryRun `
        -Quiet

      $result.totalCommits | Should -Be 1
      $result.candidates.totalCommits | Should -Be 1
      $commit = $result.commits[0]
      $commit.comparePaths.Count | Should -Be 1
      $commit.comparePaths[0] | Should -Match 'resource/plugins/Sample.vi'
      $commit.skipped.Count | Should -Be 0
    }
    finally {
      Pop-Location
    }
  }
}

