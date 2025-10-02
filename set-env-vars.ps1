$ErrorActionPreference='Stop'
$env:LV_BASE_VI = (Resolve-Path -LiteralPath './Base.vi').Path
$env:LV_HEAD_VI = (Resolve-Path -LiteralPath './Head.vi').Path
Write-Host "LV_BASE_VI=$env:LV_BASE_VI"
Write-Host "LV_HEAD_VI=$env:LV_HEAD_VI"
