Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
  Guard test to prevent reintroduction of legacy artifact names Base.vi/Head.vi.
.DESCRIPTION
  Scans scripts, tests, module code, and select documentation for the deprecated
  artifact filenames. Exceptions: CHANGELOG (historical context), issues-drafts
  (issue descriptions), and release/migration documentation files.
#>

Describe 'Legacy artifact name guard (Base.vi / Head.vi)' -Tag 'Unit','Guard' {
  BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    
    # Allowlist: files/directories that legitimately reference legacy names
    $allowlist = @(
      'CHANGELOG.md'
      'issues-drafts'
      'PR_NOTES.md'
      'ROLLBACK_PLAN.md'
      'RELEASE_NOTES_v0.4.1.md'
      'POST_RELEASE_FOLLOWUPS.md'
      'IMPLEMENTATION_STATUS.md'
      'IMPLEMENTATION_STATUS_v0.5.0.md'
      'TAG_PREP_CHECKLIST.md'
      'README.md'  # Contains breaking change migration notice
      'Guard.LegacyArtifactNames.Tests.ps1'  # This test file itself
      '.git'
    )
    
    # Build grep exclude arguments
    $excludeArgs = @()
    foreach ($item in $allowlist) {
      $excludeArgs += '--exclude-dir'
      $excludeArgs += $item
      $excludeArgs += '--exclude'
      $excludeArgs += $item
    }
  }
  
  It 'finds no Base.vi references in scripts, tests, or module code (excluding allowlist)' {
    $pattern = 'Base\.vi'
    $args = @('-r', '-l', $pattern, '--include=*.ps1', '--include=*.psm1', '--include=*.psd1') + $excludeArgs + @($repoRoot)
    $result = & grep @args 2>&1 | Where-Object { $_ -notmatch '^grep:' }
    
    if ($result) {
      $msg = "Found legacy 'Base.vi' references in:`n$($result -join "`n")"
      throw $msg
    }
    
    $result | Should -BeNullOrEmpty
  }
  
  It 'finds no Head.vi references in scripts, tests, or module code (excluding allowlist)' {
    $pattern = 'Head\.vi'
    $args = @('-r', '-l', $pattern, '--include=*.ps1', '--include=*.psm1', '--include=*.psd1') + $excludeArgs + @($repoRoot)
    $result = & grep @args 2>&1 | Where-Object { $_ -notmatch '^grep:' }
    
    if ($result) {
      $msg = "Found legacy 'Head.vi' references in:`n$($result -join "`n")"
      throw $msg
    }
    
    $result | Should -BeNullOrEmpty
  }
  
  It 'confirms VI1.vi and VI2.vi artifact files exist at repository root' {
    $vi1 = Join-Path $repoRoot 'VI1.vi'
    $vi2 = Join-Path $repoRoot 'VI2.vi'
    
    Test-Path $vi1 | Should -BeTrue -Because 'VI1.vi is the canonical base artifact'
    Test-Path $vi2 | Should -BeTrue -Because 'VI2.vi is the canonical head artifact'

    # Phase 1 extended guard: ensure tracking & minimal size
    $tracked = (& git ls-files) -split "`n" | Where-Object { $_ }
    $tracked | Should -Contain 'VI1.vi' -Because 'Fixture must be git-tracked'
    $tracked | Should -Contain 'VI2.vi' -Because 'Fixture must be git-tracked'

    $minBytes = 32
    (Get-Item $vi1).Length | Should -BeGreaterThan $minBytes -Because 'Fixture should not be truncated'
    (Get-Item $vi2).Length | Should -BeGreaterThan $minBytes -Because 'Fixture should not be truncated'
  }
}
