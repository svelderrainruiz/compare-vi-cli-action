#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Resolve-VIHistorySlice' -Tag 'Unit' {
  BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:ModulePath = Join-Path $script:RepoRoot 'tools' 'VIHistorySlice.psm1'
    $script:ScriptPath = Join-Path $script:RepoRoot 'tools' 'Resolve-VIHistorySlice.ps1'
    Import-Module $script:ModulePath -Force
    $script:NewTestGitRepository = {
      param([string]$Path)

      New-Item -ItemType Directory -Path $Path -Force | Out-Null
      Push-Location $Path
      try {
        git init --quiet | Out-Null
        git config user.name 'Test Bot' | Out-Null
        git config user.email 'bot@example.com' | Out-Null
        git branch -M develop | Out-Null
      } finally {
        Pop-Location
      }
    }
    $script:WriteSelectorFile = {
      param([string]$Path, [hashtable]$Selector)
      ($Selector | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Path -Encoding utf8
    }
  }

  It 'resolves merge-base slices for diverged histories and writes a manifest via the wrapper script' {
    $repoPath = Join-Path $TestDrive 'merge-base-repo'
    & $script:NewTestGitRepository $repoPath

    Push-Location $repoPath
    try {
      Set-Content -LiteralPath 'Target.vi' -Value 'base'
      git add Target.vi | Out-Null
      git commit --quiet -m 'base target' | Out-Null
      $baseSha = (git rev-parse HEAD).Trim()

      git checkout --quiet -b feature/history | Out-Null
      Set-Content -LiteralPath 'Target.vi' -Value 'feature-1'
      git add Target.vi | Out-Null
      git commit --quiet -m 'feature touches target' | Out-Null
      $featureSha = (git rev-parse HEAD).Trim()

      git checkout --quiet develop | Out-Null
      Set-Content -LiteralPath 'notes.txt' -Value 'develop-1'
      git add notes.txt | Out-Null
      git commit --quiet -m 'develop diverges' | Out-Null
      Set-Content -LiteralPath 'notes.txt' -Value 'develop-2'
      git add notes.txt | Out-Null
      git commit --quiet -m 'develop diverges again' | Out-Null
      $developTipSha = (git rev-parse HEAD).Trim()

      git checkout --quiet feature/history | Out-Null

      $selectorPath = Join-Path $TestDrive 'merge-base-selector.json'
      $manifestPath = Join-Path $TestDrive 'merge-base-manifest.json'
      & $script:WriteSelectorFile $selectorPath ([ordered]@{
        schema = 'vi-history/slice-selector@v1'
        repoPath = $repoPath
        targetPath = 'Target.vi'
        headRef = 'HEAD'
        baselineRef = $developTipSha
        baselineMode = 'merge-base'
        historyMode = 'first-parent'
        maxCommitCount = 8
        maxPairs = 4
        selectionPolicyVersion = 1
      })

      $rawJson = & pwsh -NoLogo -NoProfile -File $script:ScriptPath -SelectorPath $selectorPath -OutputPath $manifestPath
      $LASTEXITCODE | Should -Be 0
      $manifestPath | Should -Exist

      $manifest = $rawJson | ConvertFrom-Json -Depth 16
      $manifest.schema | Should -Be 'vi-history/slice-manifest@v1'
      $manifest.resolved.baselineSha | Should -Be $baseSha
      $manifest.resolved.mergeBaseSha | Should -Be $baseSha
      $manifest.resolved.headSha | Should -Be $featureSha
      $manifest.resolved.rangeExpression | Should -Be ("{0}..{1}" -f $baseSha, $featureSha)
      [int]$manifest.resolved.candidateCommitCount | Should -Be 1
      @($manifest.candidateCommits) | Should -Be @($featureSha)
      [int]$manifest.resolved.pairCount | Should -Be 1
      $manifest.pairs[0].baseSha | Should -Be $baseSha
      $manifest.pairs[0].headSha | Should -Be $featureSha
      $manifest.sliceDigest | Should -Match '^[a-f0-9]{64}$'
    } finally {
      Pop-Location
    }
  }

  It 'keeps the slice digest stable between symbolic and explicit head references' {
    $repoPath = Join-Path $TestDrive 'digest-repo'
    & $script:NewTestGitRepository $repoPath

    Push-Location $repoPath
    try {
      Set-Content -LiteralPath 'Target.vi' -Value 'base'
      git add Target.vi | Out-Null
      git commit --quiet -m 'base target' | Out-Null
      $baseSha = (git rev-parse HEAD).Trim()

      Set-Content -LiteralPath 'Target.vi' -Value 'head'
      git add Target.vi | Out-Null
      git commit --quiet -m 'head target' | Out-Null
      $headSha = (git rev-parse HEAD).Trim()
    } finally {
      Pop-Location
    }

    $selectorHead = [pscustomobject][ordered]@{
      schema = 'vi-history/slice-selector@v1'
      repoPath = $repoPath
      targetPath = 'Target.vi'
      headRef = 'HEAD'
      baselineRef = $baseSha
      baselineMode = 'explicit'
      historyMode = 'first-parent'
      maxCommitCount = 4
      maxPairs = 4
      selectionPolicyVersion = 1
    }
    $selectorSha = [pscustomobject][ordered]@{
      schema = 'vi-history/slice-selector@v1'
      repoPath = $repoPath
      targetPath = 'Target.vi'
      headRef = $headSha
      baselineRef = $baseSha
      baselineMode = 'explicit'
      historyMode = 'first-parent'
      maxCommitCount = 4
      maxPairs = 4
      selectionPolicyVersion = 1
    }

    $manifestFromHead = Resolve-VIHistorySliceManifest -Selector $selectorHead
    $manifestFromSha = Resolve-VIHistorySliceManifest -Selector $selectorSha

    $manifestFromHead.resolved.headSha | Should -Be $headSha
    $manifestFromSha.resolved.headSha | Should -Be $headSha
    $manifestFromHead.sliceDigest | Should -Be $manifestFromSha.sliceDigest
    @($manifestFromHead.candidateCommits) | Should -Be @($manifestFromSha.candidateCommits)
  }

  It 'supports git worktrees as selector repo roots' {
    $repoPath = Join-Path $TestDrive 'worktree-repo'
    $worktreePath = Join-Path $TestDrive 'feature-worktree'
    & $script:NewTestGitRepository $repoPath

    Push-Location $repoPath
    try {
      Set-Content -LiteralPath 'Target.vi' -Value 'base'
      git add Target.vi | Out-Null
      git commit --quiet -m 'base target' | Out-Null
      $baseSha = (git rev-parse HEAD).Trim()
      git branch feature/worktree | Out-Null
      git worktree add --quiet $worktreePath feature/worktree | Out-Null
    } finally {
      Pop-Location
    }

    Push-Location $worktreePath
    try {
      git config user.name 'Test Bot' | Out-Null
      git config user.email 'bot@example.com' | Out-Null
      Set-Content -LiteralPath 'Target.vi' -Value 'worktree-change'
      git add Target.vi | Out-Null
      git commit --quiet -m 'worktree target change' | Out-Null
      $worktreeHeadSha = (git rev-parse HEAD).Trim()
    } finally {
      Pop-Location
    }

    $manifest = Resolve-VIHistorySliceManifest -Selector ([pscustomobject][ordered]@{
      schema = 'vi-history/slice-selector@v1'
      repoPath = $worktreePath
      targetPath = 'Target.vi'
      headRef = 'HEAD'
      baselineRef = $baseSha
      baselineMode = 'explicit'
      historyMode = 'first-parent'
      maxCommitCount = 4
      maxPairs = 4
      selectionPolicyVersion = 1
    })

    $manifest.repoRoot | Should -Be $worktreePath
    $manifest.resolved.headSha | Should -Be $worktreeHeadSha
    $manifest.resolved.baselineSha | Should -Be $baseSha
    @($manifest.candidateCommits) | Should -Be @($worktreeHeadSha)
  }

  It 'keeps candidate history intact while truncating selected pairs to the most recent commits' {
    $repoPath = Join-Path $TestDrive 'truncate-repo'
    & $script:NewTestGitRepository $repoPath

    Push-Location $repoPath
    try {
      Set-Content -LiteralPath 'Target.vi' -Value 'base'
      git add Target.vi | Out-Null
      git commit --quiet -m 'base target' | Out-Null
      $baseSha = (git rev-parse HEAD).Trim()

      $selectedShas = @()
      foreach ($value in @('one', 'two', 'three')) {
        Set-Content -LiteralPath 'Target.vi' -Value $value
        git add Target.vi | Out-Null
        git commit --quiet -m ("target {0}" -f $value) | Out-Null
        $selectedShas += (git rev-parse HEAD).Trim()
      }
      $headSha = (git rev-parse HEAD).Trim()
    } finally {
      Pop-Location
    }

    $manifest = Resolve-VIHistorySliceManifest -Selector ([pscustomobject][ordered]@{
      schema = 'vi-history/slice-selector@v1'
      repoPath = $repoPath
      targetPath = 'Target.vi'
      headRef = $headSha
      baselineRef = $baseSha
      baselineMode = 'explicit'
      historyMode = 'first-parent'
      maxCommitCount = 8
      maxPairs = 2
      selectionPolicyVersion = 1
    })

    [int]$manifest.resolved.candidateCommitCount | Should -Be 3
    [int]$manifest.resolved.commitCount | Should -Be 2
    $manifest.resolved.truncated | Should -BeTrue
    @($manifest.candidateCommits) | Should -Be @($selectedShas)
    @($manifest.commits | ForEach-Object { [string]$_.sha }) | Should -Be @($selectedShas[1], $selectedShas[2])
    [int]$manifest.resolved.pairCount | Should -Be 2
  }
}
