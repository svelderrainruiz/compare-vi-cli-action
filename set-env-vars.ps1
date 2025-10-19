$ErrorActionPreference='Stop'
$env:LV_BASE_VI = (Resolve-Path -LiteralPath './VI1.vi').Path
$env:LV_HEAD_VI = (Resolve-Path -LiteralPath './VI2.vi').Path
if (-not $env:COMPAREVI_TOOLS_IMAGE) {
    $env:COMPAREVI_TOOLS_IMAGE = 'ghcr.io/labview-community-ci-cd/comparevi-tools:latest'
}
Write-Host "LV_BASE_VI=$env:LV_BASE_VI"
Write-Host "LV_HEAD_VI=$env:LV_HEAD_VI"
Write-Host "COMPAREVI_TOOLS_IMAGE=$env:COMPAREVI_TOOLS_IMAGE"
