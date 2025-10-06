<#
.SYNOPSIS
  Fails when tracked build artifacts are present in the repository.

.DESCRIPTION
  Scans git-tracked files for common build output locations and test result folders:
  - src/**/obj/**
  - src/**/bin/**
  - **/TestResults/**

  Supports an allowlist of wildcard patterns to exclude specific paths from failing the check.
  The allowlist can be provided via the -AllowPatterns parameter or the environment variable
  ALLOWLIST_TRACKED_ARTIFACTS (semicolon-separated).

  When matches are found, prints offending paths, writes a concise block to the job step summary
  (when available), and exits with code 3.
#>
[CmdletBinding()]
param(
  [string[]]$AllowPatterns,
  [string]$AllowListPath = '.ci/build-artifacts-allow.txt'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-PathUnix([string]$p) {
  if (-not $p) { return $p }
  return $p -replace '\\','/'
}

function Match-Any($value,[string[]]$patterns){
  if (-not $patterns -or $patterns.Count -eq 0) { return $false }
  foreach($pat in $patterns){ if ($value -like $pat) { return $true } }
  return $false
}

# Gather allowlist entries
$envAllow = @()
if ($env:ALLOWLIST_TRACKED_ARTIFACTS) {
  $envAllow = $env:ALLOWLIST_TRACKED_ARTIFACTS -split ';'
}
if ($AllowPatterns) {
  $envAllow += $AllowPatterns
}
# File-based allowlist (one glob per non-empty, non-comment line)
if ($AllowListPath -and (Test-Path -LiteralPath $AllowListPath -PathType Leaf)) {
  try {
    $lines = Get-Content -LiteralPath $AllowListPath -ErrorAction Stop | Where-Object { $_ -and ($_.Trim()).Length -gt 0 } | ForEach-Object { $_.Trim() }
    $lines = $lines | Where-Object { -not ($_.StartsWith('#')) }
    if ($lines) { $envAllow += $lines }
  } catch { Write-Host "::notice::Failed to read allowlist file: $AllowListPath ($_ )" }
}

# Collect tracked files
$tracked = & git ls-files | ForEach-Object { Normalize-PathUnix $_ }

# Patterns to flag (PowerShell wildcard globs, evaluated against forward-slash paths)
$flagPatterns = @(
  'src/*/obj/*','src/*/*/obj/*','src/*/*/*/obj/*','src/**/obj/*',
  'src/*/bin/*','src/*/*/bin/*','src/*/*/*/bin/*','src/**/bin/*',
  '*/TestResults/*','**/TestResults/*'
)

$offenders = @()
foreach($f in $tracked){
  $hit = $false
  foreach($p in $flagPatterns){ if ($f -like $p) { $hit = $true; break } }
  if (-not $hit) { continue }
  if (Match-Any $f $envAllow) { continue }
  $offenders += $f
}

if ($offenders.Count -gt 0) {
  Write-Host 'Tracked build artifacts detected:'
  $offenders | ForEach-Object { Write-Host " - $_" }
  if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @('### Tracked Build Artifacts Detected','',"Count: $($offenders.Count)")
    foreach($o in $offenders){ $lines += ('- ' + $o) }
    $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  }
  exit 3
} else {
  Write-Host 'No tracked build artifacts found.'
}
