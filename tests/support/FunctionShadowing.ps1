<#!
.SYNOPSIS
  Provides a helper to temporarily shadow (override) an existing command with a function definition
  during execution of a script block, restoring the original definition afterwards.

.DESCRIPTION
  Invoke-WithFunctionShadow is a lightweight alternative to Pester Mock when nested Pester
  invocations or dispatcher-driven runs can invalidate the mock registry. It works by placing
  a function of the specified name in the Function: drive (which takes precedence over cmdlets),
  running the supplied body, then restoring (or removing) the function so subsequent tests see
  the original command behavior.

  This is intentionally minimal and has no external dependencies. Use inside test contexts only.

.PARAMETER Name
  The command/function name to shadow (e.g. 'Get-Module').

.PARAMETER Definition
  The script block implementing the temporary function. Should include any needed parameters.

.PARAMETER Body
  The work to perform while the shadow is active. The result of this block is returned.

.EXAMPLE
  Invoke-WithFunctionShadow -Name Get-Module -Definition {
    param([switch]$ListAvailable,[string]$Name)
    if ($ListAvailable -and $Name -eq 'Pester') { return [pscustomobject]@{ Name='Pester'; Version=[version]'5.7.1' } }
    Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
  } -Body {
    Test-PesterAvailable | Should -BeTrue
  }
#>
function Invoke-WithFunctionShadow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Definition,
    [Parameter(Mandatory)][scriptblock]$Body
  )

  # Capture any existing function definition (if present). Cmdlets won't appear in Function: drive.
  $hadExistingFunction = $false
  $existingScriptBlock = $null
  if (Test-Path "Function:$Name") {
    $existing = Get-Command -Name $Name -CommandType Function -ErrorAction SilentlyContinue
    if ($existing) {
      $hadExistingFunction = $true
      $existingScriptBlock = $existing.ScriptBlock
    }
  }

  try {
    # Install shadow function
    Set-Item -Path "Function:$Name" -Value $Definition -Force
    # Execute body and return its output
    & $Body
  } finally {
    # Remove our shadow
    Remove-Item -Path "Function:$Name" -ErrorAction SilentlyContinue
    # Restore prior function if one existed
    if ($hadExistingFunction -and $existingScriptBlock) {
      Set-Item -Path "Function:$Name" -Value $existingScriptBlock -Force
    }
  }
}
