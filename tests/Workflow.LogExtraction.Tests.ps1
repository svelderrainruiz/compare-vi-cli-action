Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Workflow log extraction' -Tag 'Unit' {
  BeforeAll {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
  }

  It 'finds parameter conversion error inside an extracted job log' {
    $sourceDir = Join-Path $TestDrive 'log-src'
    $zipPath = Join-Path $TestDrive 'job-log.zip'
    $extractDir = Join-Path $TestDrive 'log-extracted'

    New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

    $logContent = @"
2025-10-07T14:25:46Z ##[group]Run ./Invoke-PesterTests.ps1 -TestsPath tests
2025-10-07T14:25:46Z ##[error]Cannot process argument transformation on parameter 'TimeoutMinutes'. Cannot convert value "-ResultsPath" to type "System.Double". Error: "The input string '-ResultsPath' was not in a correct format."
2025-10-07T14:25:47Z ##[endgroup]
"@

    $logFile = Join-Path $sourceDir '1_Test/1.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null
    Set-Content -LiteralPath $logFile -Value $logContent -Encoding utf8

    [System.IO.Compression.ZipFile]::CreateFromDirectory($sourceDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $extracted = Get-ChildItem -Path $extractDir -Recurse -File | Select-Object -First 1
    $extracted | Should -Not -BeNullOrEmpty

    $content = Get-Content -LiteralPath $extracted.FullName -Raw
    $content | Should -Match "Cannot process argument transformation on parameter 'TimeoutMinutes'"
    $content | Should -Match "The input string '-ResultsPath' was not in a correct format"
  }
}
