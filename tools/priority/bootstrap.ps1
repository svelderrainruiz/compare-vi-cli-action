#Requires -Version 7.0
[CmdletBinding()]
param(
  [switch]$VerboseHooks,
  [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Npm {
  param(
    [Parameter(Mandatory=$true)][string]$Script,
    [switch]$AllowFailure
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'npm'
  $psi.ArgumentList.Add('run')
  $psi.ArgumentList.Add($Script)
  $psi.WorkingDirectory = (Resolve-Path '.').Path
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()

  if ($stdout) { Write-Host $stdout.TrimEnd() }
  if ($stderr) { Write-Warning $stderr.TrimEnd() }

  if ($proc.ExitCode -ne 0 -and -not $AllowFailure) {
    throw "npm run $Script exited with code $($proc.ExitCode)"
  }
}

Write-Host '[bootstrap] Detecting hook plane…'
Invoke-Npm -Script 'hooks:plane' -AllowFailure

Write-Host '[bootstrap] Running hook preflight…'
Invoke-Npm -Script 'hooks:preflight' -AllowFailure

if ($VerboseHooks) {
  Write-Host '[bootstrap] Running hook parity diff…'
  Invoke-Npm -Script 'hooks:multi' -AllowFailure:$true
  Write-Host '[bootstrap] Validating hook summary schema…'
  Invoke-Npm -Script 'hooks:schema' -AllowFailure:$true
}

if (-not $PreflightOnly) {
  Write-Host '[bootstrap] Syncing standing priority snapshot…'
  Invoke-Npm -Script 'priority:sync' -AllowFailure:$true
  Write-Host '[bootstrap] Showing router plan…'
  Invoke-Npm -Script 'priority:show' -AllowFailure:$true
}

Write-Host '[bootstrap] Bootstrapping complete.'
