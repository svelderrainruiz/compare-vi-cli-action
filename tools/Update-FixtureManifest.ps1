${ErrorActionPreference} = 'Stop'
<#!
.SYNOPSIS
  Regenerates fixtures.manifest.json with current SHA256 & size metadata.
.DESCRIPTION
  Safely updates the manifest used by Validate-Fixtures. Requires explicit -Allow to proceed
  unless -Force supplied. Intended for controlled fixture evolution commits including
  commit message token [fixture-update].
#>
param(
  [switch]$Allow,
  [switch]$Force,
  [string]$Output = 'fixtures.manifest.json'
)

if (-not ($Allow -or $Force)) { Write-Error 'Refusing to update manifest without -Allow (or -Force)'; exit 1 }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
$targets = @('VI1.vi','VI2.vi')
$items = @()
foreach ($t in $targets) {
  $p = Join-Path $repoRoot $t
  if (-not (Test-Path -LiteralPath $p)) { Write-Error "Fixture missing: $t"; exit 2 }
  $len = (Get-Item -LiteralPath $p).Length
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant()
  $role = if ($t -eq 'VI1.vi') { 'base' } else { 'head' }
  $items += [pscustomobject]@{ path=$t; sha256=$hash; minBytes=32; role=$role }
}

$manifest = [ordered]@{
  schema = 'fixture-manifest-v1'
  generatedAt = (Get-Date).ToString('o')
  items = $items
}
$json = $manifest | ConvertTo-Json -Depth 4
Set-Content -LiteralPath (Join-Path $repoRoot $Output) -Value $json -Encoding UTF8
Write-Host "Updated manifest: $Output"
