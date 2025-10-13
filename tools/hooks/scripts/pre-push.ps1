#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = git rev-parse --show-toplevel
Push-Location $repoRoot
try {
  Write-Output '[pre-push] Running tools/PrePush-Checks.ps1'
  & "$repoRoot/tools/PrePush-Checks.ps1"
  if ($LASTEXITCODE -ne 0) {
    throw "PrePush-Checks.ps1 exited with code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

Write-Output '[pre-push] OK'
