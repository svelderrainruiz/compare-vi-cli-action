<#!
.SYNOPSIS
  Sample script to set environment variables required for CompareVI integration tests.
.DESCRIPTION
  Copies or points to existing VI files and sets LV_BASE_VI / LV_HEAD_VI for the current session.
  Adjust the paths below to real LabVIEW VI files before invoking. Not intended for production use.
#>
param(
  [string]$BaseVi = 'C:\Path\To\Base.vi',
  [string]$HeadVi = 'C:\Path\To\Head.vi'
)

if (-not (Test-Path -LiteralPath $BaseVi)) { Write-Warning "Base VI not found: $BaseVi" }
if (-not (Test-Path -LiteralPath $HeadVi)) { Write-Warning "Head VI not found: $HeadVi" }

$env:LV_BASE_VI = (Resolve-Path -LiteralPath $BaseVi).Path
$env:LV_HEAD_VI = (Resolve-Path -LiteralPath $HeadVi).Path

Write-Host "LV_BASE_VI=$env:LV_BASE_VI" -ForegroundColor Cyan
Write-Host "LV_HEAD_VI=$env:LV_HEAD_VI" -ForegroundColor Cyan

if (-not (Test-Path 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe')) {
  Write-Warning 'LVCompare.exe not found at canonical path.'
}

Write-Host 'Environment variables set for current PowerShell session.' -ForegroundColor Green
