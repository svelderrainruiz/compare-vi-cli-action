$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $root 'scripts' 'Render-CompareReport.ps1'

& $renderer `
  -Command '"C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe" "C:\\VIs\\a.vi" "C:\\VIs\\b.vi" --log "C:\\Temp\\Spaced Path\\x"' `
  -ExitCode 1 `
  -Diff 'true' `
  -CliPath 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe' `
  -OutputPath (Join-Path $root 'tests' 'results' 'compare-report.mock.html')

Write-Host 'Mock HTML report generated.'
