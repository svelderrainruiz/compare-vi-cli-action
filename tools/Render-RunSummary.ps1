param(
  [Parameter(Position=0)][Alias('Path')][string]$InputFile,
  [ValidateSet('Markdown','Text')][string]$Format = 'Markdown',
  [string]$OutFile,
  [switch]$AppendStepSummary,
  [string]$Title = 'Compare Loop Run Summary'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSCommandPath) '..' 'module' 'RunSummary' 'RunSummary.psm1'
if (Test-Path -LiteralPath $modulePath) { Import-Module $modulePath -Force }
$resolved = $InputFile
if (-not $resolved -and $env:RUNSUMMARY_INPUT_FILE) { $resolved = $env:RUNSUMMARY_INPUT_FILE }
if (-not $resolved) { throw 'Input file not provided (argument or RUNSUMMARY_INPUT_FILE).' }
$content = Convert-RunSummary -InputFile $resolved -Format $Format -AsString -Title $Title -AppendStepSummary:$AppendStepSummary
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $content, [Text.Encoding]::UTF8) }
Write-Host $content
