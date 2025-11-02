#Requires -Version 7.0

Describe 'Simulate-IconEditorBuild.ps1' -Tag 'IconEditor','Simulation','Unit' {
  BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:scriptPath = Join-Path $script:repoRoot 'tools' 'icon-editor' 'Simulate-IconEditorBuild.ps1'
    $script:fixturePath = Join-Path $script:repoRoot 'tests' 'fixtures' 'icon-editor' 'ni_icon_editor-1.4.1.948.vip'
  }

  It 'materialises fixture artifacts and manifest' {
    $resultsRoot = Join-Path $TestDrive 'simulate-results'
    $expected = @{
      major  = 9
      minor  = 9
      patch  = 9
      build  = 9
      commit = 'deadbeef'
    }

    $manifest = & $script:scriptPath `
      -FixturePath $script:fixturePath `
      -ResultsRoot $resultsRoot `
      -ExpectedVersion $expected

    $manifest | Should -Not -BeNullOrEmpty
    $manifest.simulation.enabled | Should -BeTrue
    $manifest.version.fixture.raw | Should -Be '1.4.1.948'
    $manifest.version.expected.commit | Should -Be 'deadbeef'

    $vipMain = Join-Path $resultsRoot 'ni_icon_editor-1.4.1.948.vip'
    $vipSystem = Join-Path $resultsRoot 'ni_icon_editor_system-1.4.1.948.vip'
    Test-Path -LiteralPath $vipMain | Should -BeTrue
    Test-Path -LiteralPath $vipSystem | Should -BeTrue

    Test-Path -LiteralPath (Join-Path $resultsRoot 'lv_icon_x86.lvlibp') | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $resultsRoot 'lv_icon_x64.lvlibp') | Should -BeTrue

    $summaryPath = Join-Path $resultsRoot 'package-smoke-summary.json'
    Test-Path -LiteralPath $summaryPath | Should -BeTrue
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $summary.status | Should -Be 'ok'

    Test-Path -LiteralPath (Join-Path $resultsRoot '__fixture_extract') | Should -BeFalse
  }
}
