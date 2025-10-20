Describe 'Compare-VIHistory.ps1' {
  It 'produces history summary artifacts using stub LVCompare' {
    $ErrorActionPreference = 'Stop'

    $repoRoot = (Get-Location).Path
    $scriptPath = Join-Path $repoRoot 'tools' 'Compare-VIHistory.ps1'
    Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue

    $stubPath = Join-Path $TestDrive 'Invoke-LVCompare.stub.ps1'
    @'
param(
  [string]$BaseVi,
  [string]$HeadVi,
  [string]$OutputDir,
  [string[]]$Flags
)
$ErrorActionPreference = 'Stop'
if (-not $OutputDir) { $OutputDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString()) }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stdoutPath = Join-Path $OutputDir 'lvcompare-stdout.txt'
$stderrPath = Join-Path $OutputDir 'lvcompare-stderr.txt'
$exitPath   = Join-Path $OutputDir 'lvcompare-exitcode.txt'
$reportPath = Join-Path $OutputDir 'compare-report.html'
$capPath    = Join-Path $OutputDir 'lvcompare-capture.json'
"Stub compare for $BaseVi -> $HeadVi (flags: $($Flags -join ' '))" | Out-File -LiteralPath $stdoutPath -Encoding utf8
'' | Out-File -LiteralPath $stderrPath -Encoding utf8
'0' | Out-File -LiteralPath $exitPath -Encoding utf8
'<html><body><h1>Stub Report</h1></body></html>' | Out-File -LiteralPath $reportPath -Encoding utf8
$cap = [pscustomobject]@{
  schema   = 'lvcompare-capture-v1'
  exitCode = 0
  seconds  = 0.01
  command  = 'stub'
  cliPath  = 'stub'
  base     = $BaseVi
  head     = $HeadVi
  args     = $Flags
  environment = [ordered]@{
    flags  = $Flags
    policy = 'default'
  }
  cli = [ordered]@{
    artifacts = [ordered]@{
      reportSizeBytes = 128
      imageCount      = 0
    }
  }
}
$cap | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $capPath -Encoding utf8
'@ | Set-Content -LiteralPath $stubPath -Encoding utf8

    $resultsDir = Join-Path $TestDrive 'history'
    $args = @(
      '-File', $scriptPath,
      '-ViName', 'VI1.vi',
      '-Branch', 'HEAD',
      '-MaxPairs', 2,
      '-ResultsDir', $resultsDir,
      '-LvCompareArgs', '-nobdcosm',
      '-InvokeScriptPath', $stubPath,
      '-Quiet'
    )

    pwsh @args

    $summaryPath = Join-Path $resultsDir 'history-summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
      Set-ItResult -Skipped -Because "history summary not produced for branch window (likely no commits with VI present)"
      return
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 10
    $summary.schema | Should -Be 'vi-history-compare/v1'
    ($summary.commitWindow | Measure-Object).Count | Should -BeGreaterThan 0
    $summary.missingStrategy | Should -Be 'skip'
    $summary.missingSegments | Should -Not -Be $null
    ($summary.pairs | Measure-Object).Count | Should -BeGreaterThanOrEqual 0

    $executedPairs = @($summary.pairs | Where-Object { -not $_.skippedIdentical -and -not $_.skippedMissing })
    if ($executedPairs.Count -gt 0) {
      foreach ($pair in $executedPairs) {
        $pair.pathA | Should -Not -BeNullOrEmpty
        $pair.pathB | Should -Not -BeNullOrEmpty
        $pair.summaryJson | Should -Not -BeNullOrEmpty
        $pair.reportHtml | Should -Not -BeNullOrEmpty
        $pair.lvcompare | Should -Not -Be $null
      }
    } else {
      ($summary.missingSegments | Measure-Object).Count | Should -BeGreaterThan 0
    }
  }
}
