<# 
.SYNOPSIS
  File-backed single-execution guard for multi-step workflows.

.DESCRIPTION
  Persists marker files under a supplied scope directory so cooperative scripts
  can skip duplicate actions within the same pipeline run. Designed for post-run
  cleanup steps that might be invoked multiple times (job retries, finally blocks).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Once {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][ScriptBlock]$Action,
    [string]$ScopeDirectory = (Join-Path (Get-Location).Path 'tests/results/_agent/post'),
    [switch]$WhatIf
  )

  if ([string]::IsNullOrWhiteSpace($Key)) { throw "Invoke-Once: Key cannot be empty." }
  if (-not (Test-Path -LiteralPath $ScopeDirectory)) {
    New-Item -ItemType Directory -Force -Path $ScopeDirectory | Out-Null
  }

  $normalized = ($Key -replace '[^a-zA-Z0-9\-_]', '_')
  $markerPath = Join-Path $ScopeDirectory ("once-{0}.marker" -f $normalized)

  if (Test-Path -LiteralPath $markerPath) {
    Write-Verbose ("Invoke-Once: key '{0}' already recorded at {1}." -f $Key, $markerPath)
    return $false
  }

  if (-not $WhatIf) {
    & $Action
  }

  # Marker records UTC timestamp and original key for diagnostics.
  $payload = [pscustomobject]@{
    key = $Key
    at  = (Get-Date).ToUniversalTime().ToString('o')
  }
  $payload | ConvertTo-Json -Depth 3 | Out-File -FilePath $markerPath -Encoding utf8
  return $true
}

Export-ModuleMember -Function Invoke-Once
