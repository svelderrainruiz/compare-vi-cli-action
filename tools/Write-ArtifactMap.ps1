<#
.SYNOPSIS
  Append a detailed artifact map (exists, size, modified) to job summary.
#>
[CmdletBinding()]
param(
  [string[]]$Paths,
  [string]$PathsList,
  [string]$Title = 'Artifacts Map'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

# Normalize inputs: support either -Paths (array) or -PathsList (semicolon/whitespace-separated)
$pathsNorm = @()
if ($Paths -and $Paths.Count -gt 0) { $pathsNorm = $Paths }
elseif ($PathsList) { $pathsNorm = @($PathsList -split '[;\s]+' | Where-Object { $_ }) }
else { $pathsNorm = @() }

function Fmt-Size([long]$bytes){ if ($bytes -lt 1024) { return "$bytes B" } if ($bytes -lt 1024*1024) { return ('{0:N1} KB' -f ($bytes/1kb)) } return ('{0:N1} MB' -f ($bytes/1mb)) }

$lines = @("### $Title",'')
$any = $false
foreach ($p in $pathsNorm) {
  if ([string]::IsNullOrWhiteSpace($p)) { continue }
  if (Test-Path -LiteralPath $p) {
    $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) {
      $lines += ('- {0} ({1}, {2:yyyy-MM-dd HH:mm:ss})' -f $p, (Fmt-Size $item.Length), $item.LastWriteTime)
      $any = $true
    } elseif ($item -and $item.PSIsContainer) {
      $files = Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue
      $count = @($files).Count
      $size = ($files | Measure-Object -Property Length -Sum).Sum
      $lines += ('- {0} (dir: {1} files, {2})' -f $p, $count, (Fmt-Size $size))
      $any = $true
    } else {
      $lines += ('- {0} (exists)' -f $p); $any = $true
    }
  } else {
    $lines += ('- {0} (missing)' -f $p)
  }
}
if (-not $any) { $lines += '- (none found)' }
$lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
