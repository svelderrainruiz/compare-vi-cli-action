<#!
.SYNOPSIS
  Lightweight test utilities for compare-vi-cli-action Pester suites.

.DESCRIPTION
  Provides helpers intended for test code only. These are not part of the action's runtime surface.
  Current contents:
    * Invoke-WithFunctionShadow - Safe, restorable function shadowing alternative to Pester Mock for
      nested dispatcher scenarios (or when mocks are unreliable across process / nested runs).

.NOTES
  Keep this module intentionally minimal. Avoid external dependencies and heavy logic.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-WithFunctionShadow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Definition,
    [Parameter(Mandatory)][scriptblock]$Body
  )

  $path = "Function:$Name"
  $hadExisting = $false
  $orig = $null
  $existing = Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
  if ($existing) { $hadExisting = $true; $orig = $existing.ScriptBlock }

  try {
    Set-Item -Path $path -Value $Definition -Force | Out-Null
    & $Body
  } finally {
    if (Test-Path $path) { Remove-Item -Path $path -ErrorAction SilentlyContinue }
    if ($hadExisting -and $orig) { Set-Item -Path $path -Value $orig -Force | Out-Null }
  }
}

Export-ModuleMember -Function Invoke-WithFunctionShadow
