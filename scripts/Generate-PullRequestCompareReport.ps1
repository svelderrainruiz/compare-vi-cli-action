<#
.SYNOPSIS
 Generates HTML + Markdown diff summary (PR body snippet) for repository Base.vi vs Head.vi using LVCompare.
.DESCRIPTION
 Runs one real LVCompare invocation (canonical path enforced) against Base.vi & Head.vi in repo root.
 Emits:
  - HTML report file (self-contained) via Render-CompareReport.ps1
  - Markdown snippet file with key metadata + link placeholder
  - JSON summary file (command, exitCode, diff, timing)
.PARAMETER OutputDirectory
 Target directory for artifacts (created if missing). Default: ./compare-artifacts
#>
[CmdletBinding()] param(
  [string]$OutputDirectory = 'compare-artifacts'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) { throw "LVCompare not found at canonical path: $canonical" }
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$baseVi = (Resolve-Path (Join-Path $repoRoot 'Base.vi')).Path
$headVi = (Resolve-Path (Join-Path $repoRoot 'Head.vi')).Path
. (Join-Path $repoRoot 'scripts' 'CompareVI.ps1')

Write-Host "Invoking LVCompare on:`n Base=$baseVi`n Head=$headVi" -ForegroundColor Cyan
$res = Invoke-CompareVI -Base $baseVi -Head $headVi -LvComparePath $canonical -FailOnDiff:$false

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$htmlPath = Join-Path $OutputDirectory 'compare-report.html'
$renderer = Join-Path $repoRoot 'scripts' 'Render-CompareReport.ps1'
& $renderer -Command $res.Command -ExitCode $res.ExitCode -Diff ($res.Diff.ToString().ToLower()) -CliPath $res.CliPath -OutputPath $htmlPath -DurationSeconds $res.CompareDurationSeconds

$summary = [pscustomobject]@{
  base = $baseVi
  head = $headVi
  exitCode = $res.ExitCode
  diff = $res.Diff
  command = $res.Command
  compareDurationSeconds = $res.CompareDurationSeconds
  generatedUtc = [DateTime]::UtcNow.ToString('o')
}
$summaryPath = Join-Path $OutputDirectory 'compare-summary.json'
$summary | ConvertTo-Json -Depth 4 | Out-File -FilePath $summaryPath -Encoding utf8

$mdPath = Join-Path $OutputDirectory 'pr-diff-snippet.md'
$diffStatus = if ($res.Diff) { '⚠️ Differences detected' } else { '✅ No differences' }
$md = @()
$md += '### LabVIEW VI Compare'
$md += "Status: $diffStatus (exit code $($res.ExitCode))"
$md += ''
$md += '| Metric | Value |'
$md += '|--------|-------|'
$md += "| Base | $([System.IO.Path]::GetFileName($baseVi)) |"
$md += "| Head | $([System.IO.Path]::GetFileName($headVi)) |"
$md += "| Diff | $($res.Diff) |"
$md += "| Duration (s) | $([string]::Format('{0:F3}',$res.CompareDurationSeconds)) |"
$md += ''
$md += '_Attach `compare-report.html` as an artifact or render inline if your review tooling supports raw HTML._'
$md -join "`n" | Out-File -FilePath $mdPath -Encoding utf8

Write-Host "Artifacts generated:" -ForegroundColor Green
Write-Host " HTML : $htmlPath"
Write-Host " JSON : $summaryPath"
Write-Host " PR MD: $mdPath"

# Emit simple console summary for CI logs
Write-Host "--- Compare Summary ---" -ForegroundColor Magenta
Write-Host (Get-Content -LiteralPath $mdPath -Raw)

return [pscustomobject]@{ Html=$htmlPath; Summary=$summaryPath; Markdown=$mdPath; Diff=$res.Diff }
