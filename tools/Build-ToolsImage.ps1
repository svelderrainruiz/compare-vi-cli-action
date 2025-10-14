#Requires -Version 7.0
param(
  [string]$Tag = 'comparevi-tools:local',
  [switch]$NoCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  try { return (git rev-parse --show-toplevel 2>$null).Trim() } catch { return (Get-Location).Path }
}

$root = Resolve-RepoRoot
$dockerfile = Join-Path $root 'tools/docker/Dockerfile.tools'
if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
  throw "Dockerfile not found at $dockerfile"
}

$args = @('build','-f', $dockerfile, '-t', $Tag, $root)
if ($NoCache) { $args = @('build','--no-cache','-f', $dockerfile, '-t', $Tag, $root) }

Write-Host ("[tools-image] docker {0}" -f ($args -join ' ')) -ForegroundColor Cyan
& docker @args
if ($LASTEXITCODE -ne 0) { throw "docker build failed with code $LASTEXITCODE" }

Write-Host ("[tools-image] Built image: {0}" -f $Tag) -ForegroundColor Green

