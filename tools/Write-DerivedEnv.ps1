[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workspace = (Get-Location).Path
$outputPath = Join-Path $workspace 'derived-env.json'

Write-Host 'Deriving environment snapshot...'
$derive = & npm run --silent derive:env 2>&1
if ($LASTEXITCODE -ne 0) {
  $derive | ForEach-Object { Write-Host $_ }
  Write-Error "npm run derive:env failed with exit code $LASTEXITCODE"
  exit $LASTEXITCODE
}

if ($derive) {
  $derive | Set-Content -LiteralPath $outputPath -Encoding utf8
} else {
  Set-Content -LiteralPath $outputPath -Encoding utf8 -Value ''
}

$agentDir = Join-Path $workspace 'tests/results/_agent'
if (-not (Test-Path -LiteralPath $agentDir)) {
  New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
}

$dest = Join-Path $agentDir 'derived-env.json'
Copy-Item -LiteralPath $outputPath -Destination $dest -Force
Write-Host "Wrote $dest"
