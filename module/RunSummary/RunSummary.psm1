Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-RunSummary {
  <#
  .SYNOPSIS
    Render a compare loop run summary JSON (schema compare-loop-run-summary-v1) to Markdown or Text.
  .PARAMETER Path
    Path to run-summary.json emitted by Invoke-IntegrationCompareLoop (-RunSummaryJsonPath).
  .PARAMETER Format
    Output format: Markdown (default) or Text.
  .PARAMETER AsString
    Return the rendered content as a string instead of writing to host.
  .PARAMETER AppendStepSummary
    Append rendered content to GitHub Actions step summary when GITHUB_STEP_SUMMARY is set.
  .PARAMETER Title
    Optional custom heading/title.
  .OUTPUTS
    String when -AsString provided; otherwise writes to host.
  #>
  [CmdletBinding()] param(
    [Parameter(Position=0)][Alias('Path','SummaryPath')][string]$InputFile,
    [ValidateSet('Markdown','Text')][string]$Format = 'Markdown',
    [switch]$AsString,
    [switch]$AppendStepSummary,
    [string]$Title = 'Compare Loop Run Summary'
  )
  if ($env:RUNSUMMARY_DEBUG -eq '1') { Write-Host "[DEBUG Convert-RunSummary] PSBoundParameters keys=$($PSBoundParameters.Keys -join ',') PathArg='$Path'" }
  $Path = $InputFile
  if (-not $Path) {
    if ($env:RUNSUMMARY_INPUT_FILE) { $Path = $env:RUNSUMMARY_INPUT_FILE }
  }
  if (-not $Path) { throw 'Run summary file path not provided (param or RUNSUMMARY_INPUT_FILE).' }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Run summary file not found: $Path" }
  try { $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { throw "Failed to parse JSON: $_" }
  if (-not $json.schema -or $json.schema -ne 'compare-loop-run-summary-v1') { Write-Warning 'Unexpected or missing schema (expected compare-loop-run-summary-v1).' }
  $percentileLines = @()
  if ($json.percentiles) {
    foreach ($p in ($json.percentiles.PSObject.Properties.Name | Sort-Object)) {
      $percentileLines += ("| {0} | {1} s |" -f $p,$json.percentiles.$p)
    }
  }
  $histLine = if ($json.histogram) { "Histogram bins: $($json.histogram.Count)" } else { 'Histogram: (none)' }
  $base = @{
    iterations = $json.iterations
    diffs = $json.diffCount
    errors = $json.errorCount
    avg = $json.averageSeconds
    total = $json.totalSeconds
    strategy = $json.quantileStrategy
    mode = $json.mode
  }
  if ($Format -eq 'Markdown') {
    $md = @()
    $md += "### $Title"
    $md += ''
    $md += '| Metric | Value |'
    $md += '|--------|-------|'
    $md += "| Iterations | $($base.iterations) |"
    $md += "| Diffs | $($base.diffs) |"
    $md += "| Errors | $($base.errors) |"
    $md += "| Avg Duration (s) | $($base.avg) |"
    $md += "| Total Duration (s) | $($base.total) |"
    $md += "| Quantile Strategy | $($base.strategy) |"
    $md += "| Mode | $($base.mode) |"
    if ($json.rebaselineApplied) { $md += '| Rebaseline Applied | true |' }
    $md += ''
    if ($percentileLines.Count -gt 0) {
      $md += '#### Percentiles'
      $md += ''
      $md += '| Label | Seconds |'
      $md += '|-------|---------|'
      $md += $percentileLines
      $md += ''
    }
    $pctList = ($json.requestedPercentiles -join ', ')
    $md += "*Requested Percentiles:* ``$pctList``"
    $md += ''
    $md += ('*Histogram:* ' + $histLine)
    $output = ($md -join [Environment]::NewLine)
  } else {
    $lines = @()
    $lines += $Title
    $lines += ('-' * $Title.Length)
    $lines += "Iterations         : $($base.iterations)"
    $lines += "Diffs              : $($base.diffs)"
    $lines += "Errors             : $($base.errors)"
    $lines += "Avg Duration (s)   : $($base.avg)"
    $lines += "Total Duration (s) : $($base.total)"
    $lines += "Quantile Strategy  : $($base.strategy)"
    $lines += "Mode               : $($base.mode)"
    if ($json.rebaselineApplied) { $lines += 'Rebaseline Applied : true' }
    if ($percentileLines.Count -gt 0 -and $json.percentiles) {
      $lines += ''
      $lines += 'Percentiles:'
      foreach ($p in ($json.percentiles.PSObject.Properties.Name | Sort-Object)) { $lines += ("  {0,-8} {1}" -f $p,$json.percentiles.$p) }
    }
    $lines += ''
    $lines += "Requested Percentiles: $(($json.requestedPercentiles -join ', '))"
    $lines += $histLine
    $output = ($lines -join [Environment]::NewLine)
  }
  if ($AppendStepSummary) {
    $gh = $env:GITHUB_STEP_SUMMARY
    if ($gh) { try { Add-Content -LiteralPath $gh -Value $output -Encoding utf8 } catch { Write-Warning "Failed appending to step summary: $_" } } else { Write-Warning 'GITHUB_STEP_SUMMARY not set.' }
  }
  if ($AsString) { return $output } else { Write-Host $output }
}
function Render-RunSummary {
  [CmdletBinding()] param(
    [Parameter(Position=0)][Alias('Path','SummaryPath')][string]$InputFile,
    [ValidateSet('Markdown','Text')][string]$Format = 'Markdown',
    [switch]$AsString,
    [switch]$AppendStepSummary,
    [string]$Title = 'Compare Loop Run Summary'
  )
  Convert-RunSummary @PSBoundParameters
}
Export-ModuleMember -Function Convert-RunSummary,Render-RunSummary
