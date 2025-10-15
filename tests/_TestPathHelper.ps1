Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  try {
    if ($global:__REPO_ROOT -and (Test-Path -LiteralPath $global:__REPO_ROOT)) { return $global:__REPO_ROOT }
  } catch {}
  $candidates = @()
  try { if ($PSScriptRoot) { $candidates += (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path } } catch {}
  try { if ($PSCommandPath) { $candidates += (Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent $PSCommandPath) '..')).Path } } catch {}
  try {
    $git = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $git) { $candidates += $git.Trim() }
  } catch {}
  foreach ($p in ($candidates | Select-Object -Unique)) {
    if (-not [string]::IsNullOrWhiteSpace($p)) {
      $probe = Join-Path $p 'scripts'
      if (Test-Path -LiteralPath $probe) { $global:__REPO_ROOT = $p; return $p }
    }
  }
  # Fallback to current location
  return (Resolve-Path '.').Path
}

function Test-IsFastMode {
  $cacheVar = Get-Variable -Scope Script -Name __FAST_MODE_CACHE -ErrorAction SilentlyContinue
  if ($cacheVar) { return [bool]$cacheVar.Value }
  $raw = [System.Environment]::GetEnvironmentVariable('FAST_PESTER')
  if (-not $raw) { $raw = [System.Environment]::GetEnvironmentVariable('FAST_TESTS') }
  $isFast = $false
  if ($raw -and $raw.Trim()) {
    $isFast = ($raw.Trim() -match '^(?i:1|true|yes|on)$')
  }
  $script:__FAST_MODE_CACHE = $isFast
  return $isFast
}

function Invoke-TestSleep {
  [CmdletBinding(DefaultParameterSetName = 'Milliseconds')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Milliseconds')]
    [double]$Milliseconds,

    [Parameter(ParameterSetName = 'Milliseconds')]
    [double]$FastMilliseconds = 5,

    [Parameter(Mandatory, ParameterSetName = 'Seconds')]
    [double]$Seconds,

    [Parameter(ParameterSetName = 'Seconds')]
    [double]$FastSeconds = 0.05
  )

  if ($PSCmdlet.ParameterSetName -eq 'Seconds') {
    if (Test-IsFastMode) { Microsoft.PowerShell.Utility\Start-Sleep -Seconds $FastSeconds }
    else { Microsoft.PowerShell.Utility\Start-Sleep -Seconds $Seconds }
  } else {
    if (Test-IsFastMode) { Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $FastMilliseconds }
    else { Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds }
  }
}

function Get-TestIterations {
  param(
    [Parameter(Mandatory)][int]$Default,
    [int]$Fast = 3
  )
  if (Test-IsFastMode) { return $Fast }
  return $Default
}
