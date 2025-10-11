#Requires -Version 7.0
param(
  [Parameter(Mandatory)][string]$PipeName,
  [Parameter(Mandatory)][string]$ResultsDir,
  [int]$TimeoutSeconds = 15,
  [int]$Retries = 3,
  [int]$RetryDelaySeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'RunnerInvoker.psm1') -Force

if ($Retries -lt 1) { $Retries = 1 }
if ($TimeoutSeconds -lt 1) { $TimeoutSeconds = 1 }

for ($attempt = 1; $attempt -le $Retries; $attempt++) {
  try {
    $result = Invoke-RunnerRequest -ResultsDir $ResultsDir -Verb 'Ping' -CommandArgs @{ pipe = $PipeName } -TimeoutSeconds $TimeoutSeconds
    if ($result -and $result.pong) {
      Write-Host ("Invoker ping attempt #{0}: ok (pong={1})" -f $attempt, $result.pong) -ForegroundColor Green
      return
    }
    throw "Unexpected ping response: $($result | ConvertTo-Json -Compress)"
  } catch {
    if ($attempt -ge $Retries) {
      throw "Invoker ping failed after $Retries attempt(s): $($_.Exception.Message)"
    }
    Write-Host ("Invoker ping attempt #{0} failed: {1}. Retrying in {2}s..." -f $attempt, $_.Exception.Message, $RetryDelaySeconds) -ForegroundColor Yellow
    Start-Sleep -Seconds ([math]::Max(1,$RetryDelaySeconds))
  }
}
