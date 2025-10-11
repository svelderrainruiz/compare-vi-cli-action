#Requires -Version 7.0
param(
  [string]$ImageName = 'compare-validate',
  [string]$Dockerfile = (Join-Path $PSScriptRoot '../../docker/validate/Dockerfile')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Tool {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required tool not found: $Name"
  }
}

Assert-Tool docker

$context = Split-Path -Path $Dockerfile -Parent
if (-not (Test-Path -LiteralPath $Dockerfile)) {
  throw "Dockerfile not found at $Dockerfile"
}

Write-Host ("[docker] Building {0} from {1}" -f $ImageName, $Dockerfile)
docker build -f $Dockerfile -t $ImageName $context

if ($LASTEXITCODE -ne 0) {
  throw "Docker build failed (exit=$LASTEXITCODE)"
}

Write-Host ("[docker] Image '{0}' built successfully." -f $ImageName)
