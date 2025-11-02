Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Run-LocalDiffSession.ps1' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:toolPath = Join-Path $repoRoot 'tools' 'Run-LocalDiffSession.ps1'
    Test-Path -LiteralPath $script:toolPath | Should -BeTrue
  }

  It 'archives and zips stub results' {
    $work = Join-Path $TestDrive 'session'
    New-Item -ItemType Directory -Path $work | Out-Null
    $base = Join-Path $work 'Base.vi'
    $head = Join-Path $work 'Head.vi'
    Set-Content -LiteralPath $base -Value '' -Encoding ascii
    Set-Content -LiteralPath $head -Value '' -Encoding ascii

    $resultsRoot = Join-Path $TestDrive 'results'
    $archiveDir = Join-Path $TestDrive 'archive'
    $archiveZip = Join-Path $TestDrive 'archive.zip'

    $result = & $script:toolPath `
      -BaseVi $base `
      -HeadVi $head `
      -Mode 'normal' `
      -ResultsRoot $resultsRoot `
      -UseStub `
      -Stateless `
      -CheckViServer:$false `
      -ArchiveDir $archiveDir `
      -ArchiveZip $archiveZip

    $result | Should -Not -BeNullOrEmpty
    $result.runs.Count | Should -BeGreaterThan 0

    Test-Path -LiteralPath $archiveDir -PathType Container | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $archiveDir 'local-diff-summary.json') -PathType Leaf | Should -BeTrue
    Test-Path -LiteralPath $archiveZip -PathType Leaf | Should -BeTrue

    $zipExtract = Join-Path $TestDrive 'zip-extract'
    Expand-Archive -LiteralPath $archiveZip -DestinationPath $zipExtract -Force
    Test-Path -LiteralPath (Join-Path $zipExtract 'local-diff-summary.json') -PathType Leaf | Should -BeTrue
  }
}
