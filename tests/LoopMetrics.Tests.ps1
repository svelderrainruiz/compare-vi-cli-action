Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..') | Select-Object -ExpandProperty Path
Import-Module (Join-Path $repoRoot 'module' 'CompareLoop' 'CompareLoop.psd1') -Force

Describe 'Invoke-IntegrationCompareLoop metrics enrichment (legacy test skipped)' -Tag 'Skip' {
  It 'skipped legacy metrics enrichment test (covered elsewhere)' {
    $true | Should -BeTrue
  }
}
