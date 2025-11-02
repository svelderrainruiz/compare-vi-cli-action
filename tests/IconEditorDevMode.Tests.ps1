#Requires -Version 7.0

Describe 'IconEditor dev mode helpers' -Tag 'IconEditor' {
  BeforeAll {
    $script:moduleName = 'IconEditorDevMode'
    $script:modulePath = Join-Path $PSScriptRoot '..' 'tools' 'icon-editor' 'IconEditorDevMode.psm1'
    Import-Module $script:modulePath -Force
  }

  AfterAll {
    Remove-Module $script:moduleName -Force -ErrorAction SilentlyContinue
  }

  It 'returns null state when no marker exists' {
    $repoRoot = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Path $repoRoot | Out-Null

    $state = Get-IconEditorDevModeState -RepoRoot $repoRoot
    $state.Active | Should -BeNullOrEmpty
    $state.Path | Should -Match 'dev-mode-state.json$'
  }

  It 'records dev-mode state toggles' {
    $repoRoot = Join-Path $TestDrive 'repo-state'
    New-Item -ItemType Directory -Path $repoRoot | Out-Null

    $written = Set-IconEditorDevModeState -RepoRoot $repoRoot -Active $true -Source 'test-run'
    $written.Active | Should -BeTrue
    $written.Source | Should -Be 'test-run'

    $reloaded = Get-IconEditorDevModeState -RepoRoot $repoRoot
    $reloaded.Active | Should -BeTrue
    $reloaded.Source | Should -Be 'test-run'
    Test-Path -LiteralPath $reloaded.Path | Should -BeTrue
  }

  Context 'script execution' {
    BeforeEach {
      $script:repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
      $script:iconRoot = Join-Path $script:repoRoot 'vendor' 'icon-editor'
      $script:setDir = Join-Path $script:iconRoot '.github' 'actions' 'set-development-mode'
      $script:revertDir = Join-Path $script:iconRoot '.github' 'actions' 'revert-development-mode'
      $script:toolsDir = Join-Path $script:repoRoot 'tools'
      New-Item -ItemType Directory -Path $script:setDir -Force | Out-Null
      New-Item -ItemType Directory -Path $script:revertDir -Force | Out-Null
      New-Item -ItemType Directory -Path $script:toolsDir -Force | Out-Null

      $gCliPath = Join-Path $script:repoRoot 'fake-g-cli' 'bin' 'g-cli.exe'
      New-Item -ItemType Directory -Path (Split-Path -Parent $gCliPath) -Force | Out-Null
      New-Item -ItemType File -Path $gCliPath -Value '' -Force | Out-Null

      @"
function Resolve-GCliPath { return '$gCliPath' }
Export-ModuleMember -Function Resolve-GCliPath
"@ | Set-Content -LiteralPath (Join-Path $script:toolsDir 'VendorTools.psm1') -Encoding utf8

      @'
param([string]$RelativePath)
"dev-mode:on" | Set-Content -LiteralPath (Join-Path $RelativePath 'dev-mode.txt') -Encoding utf8
'@ | Set-Content -LiteralPath (Join-Path $script:setDir 'Set_Development_Mode.ps1') -Encoding utf8

      @'
param([string]$RelativePath)
"dev-mode:off" | Set-Content -LiteralPath (Join-Path $RelativePath 'dev-mode.txt') -Encoding utf8
'@ | Set-Content -LiteralPath (Join-Path $script:revertDir 'RevertDevelopmentMode.ps1') -Encoding utf8
    }

    It 'enables development mode via helper' {
      $state = Enable-IconEditorDevelopmentMode -RepoRoot $script:repoRoot -IconEditorRoot $script:iconRoot
      $state.Active | Should -BeTrue
      (Get-Content -LiteralPath (Join-Path $script:iconRoot 'dev-mode.txt') -Raw).Trim() | Should -Be 'dev-mode:on'
    }

    It 'disables development mode via helper' {
      Set-IconEditorDevModeState -RepoRoot $script:repoRoot -Active $true -Source 'pretest' | Out-Null
      $state = Disable-IconEditorDevelopmentMode -RepoRoot $script:repoRoot -IconEditorRoot $script:iconRoot
      $state.Active | Should -BeFalse
      (Get-Content -LiteralPath (Join-Path $script:iconRoot 'dev-mode.txt') -Raw).Trim() | Should -Be 'dev-mode:off'
    }
  }

  Context 'LabVIEW.ini verification (integration)' -Tag 'IconEditor','Integration','E2E' {
    It 'round-trips dev mode toggles using LabVIEW.ini' -Tag 'Integration','E2E' {
      $repoRoot = Resolve-IconEditorRepoRoot
      $status = Test-IconEditorDevelopmentMode -RepoRoot $repoRoot
      $presentTargets = $status.Entries | Where-Object { $_.Present }
      if ($presentTargets.Count -eq 0) {
        Set-ItResult -Skip 'LabVIEW 2021 installations not detected; skipping integration dev-mode verification.'
        return
      }

      $scriptPath = Join-Path $repoRoot 'tools' 'icon-editor' 'Assert-DevModeState.ps1'
      try {
        Enable-IconEditorDevelopmentMode -RepoRoot $repoRoot | Out-Null
        $afterEnable = Test-IconEditorDevelopmentMode -RepoRoot $repoRoot
        $afterEnable.Active | Should -BeTrue
        & $scriptPath -ExpectedActive:$true | Out-Null
      }
      finally {
        Disable-IconEditorDevelopmentMode -RepoRoot $repoRoot | Out-Null
      }

      $afterDisable = Test-IconEditorDevelopmentMode -RepoRoot $repoRoot
      $afterDisable.Active | Should -BeFalse
      & $scriptPath -ExpectedActive:$false | Out-Null
    }
  }
}
