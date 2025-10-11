Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Post-Run-Cleanup.ps1' -Tag 'Unit' {
  It 'executes close helpers at most once per job' {
    $repoRoot = Join-Path $TestDrive 'repo'
    $toolsDir = Join-Path $repoRoot 'tools'
    New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $toolsDir 'PostRun') -Force | Out-Null

    $sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools' 'Post-Run-Cleanup.ps1') -Destination (Join-Path $toolsDir 'Post-Run-Cleanup.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools' 'Once-Guard.psm1') -Destination (Join-Path $toolsDir 'Once-Guard.psm1') -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools' 'PostRun' 'PostRunRequests.psm1') -Destination (Join-Path $toolsDir 'PostRun' 'PostRunRequests.psm1') -Force

    $labStub = @"
param()
exit 0
"@
    Set-Content -LiteralPath (Join-Path $toolsDir 'Close-LabVIEW.ps1') -Value $labStub -Encoding UTF8

    $lvcompareStub = @"
param()
exit 0
"@
    Set-Content -LiteralPath (Join-Path $toolsDir 'Close-LVCompare.ps1') -Value $lvcompareStub -Encoding UTF8

    Push-Location $repoRoot
    $requestsDir = Join-Path $repoRoot 'tests/results/_agent/post/requests'
    New-Item -ItemType Directory -Force -Path $requestsDir | Out-Null
    $labRequest = [ordered]@{
      name   = 'close-labview'
      source = 'test'
      at     = (Get-Date).ToUniversalTime().ToString('o')
      metadata = @{ version='2025'; bitness='64' }
    }
    $lvRequest = [ordered]@{
      name   = 'close-lvcompare'
      source = 'test'
      at     = (Get-Date).ToUniversalTime().ToString('o')
      metadata = @{ base='Base.vi'; head='Head.vi' }
    }
    $labRequest | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $requestsDir 'close-labview-test.json') -Encoding utf8
    $lvRequest | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $requestsDir 'close-lvcompare-test.json') -Encoding utf8
    @((Get-ChildItem -LiteralPath $requestsDir)).Count | Should -Be 2

    & (Join-Path $toolsDir 'Post-Run-Cleanup.ps1') -CloseLabVIEW -CloseLVCompare | Out-Null
    & (Join-Path $toolsDir 'Post-Run-Cleanup.ps1') -CloseLabVIEW -CloseLVCompare | Out-Null
    Pop-Location

    $markerDir = Join-Path $repoRoot 'tests/results/_agent/post'
    $labMarkerPath = Join-Path $markerDir 'once-close-labview.marker'
    $lvMarkerPath = Join-Path $markerDir 'once-close-lvcompare.marker'
    Test-Path -LiteralPath $labMarkerPath | Should -BeTrue
    Test-Path -LiteralPath $lvMarkerPath | Should -BeTrue
    $labMarker = Get-Content -LiteralPath $labMarkerPath -Raw | ConvertFrom-Json
    $labMarker.key | Should -Be 'close-labview'
    $lvMarker = Get-Content -LiteralPath $lvMarkerPath -Raw | ConvertFrom-Json
    $lvMarker.key | Should -Be 'close-lvcompare'
    @((Get-ChildItem -LiteralPath (Join-Path $markerDir 'requests') -ErrorAction SilentlyContinue)).Count | Should -Be 0
  }
}
