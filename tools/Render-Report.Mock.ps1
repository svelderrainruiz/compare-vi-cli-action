$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $root 'scripts' 'Render-CompareReport.ps1'

& $renderer `
  -Command 'C:\Program Files\NI\LabVIEW 2025\LVCompare.exe "C:\\VIs\\a.vi" "C:\\VIs\\b.vi" --flag "C:\\Temp\\Spaced Path\\x"' `
  -ExitCode 1 `
  -Diff 'true' `
  -CliPath 'C:\Program Files\NI\LabVIEW 2025\LVCompare.exe' `
  -OutputPath (Join-Path $root 'tests' 'results' 'compare-report.mock.html')

Write-Host 'Mock HTML report generated.'