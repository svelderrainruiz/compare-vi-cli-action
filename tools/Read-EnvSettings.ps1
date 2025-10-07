param(
  [switch]$Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Bool([string]$v,[bool]$default){
  if ($null -eq $v -or $v -eq '') { return $default }
  switch ($v.ToLowerInvariant()){
    '1' { return $true }
    'true' { return $true }
    'yes' { return $true }
    default { return $false }
  }
}

$defaults = [ordered]@{
  detectLeaks     = $true    # DETECT_LEAKS
  cleanAfter      = $false   # CLEAN_AFTER
  unblockGuard    = $false   # UNBLOCK_GUARD
  suppressUi      = $false   # LV_SUPPRESS_UI
  watchConsole    = $true    # WATCH_CONSOLE
  invokerRequired = $false   # INVOKER_REQUIRED (true on self-hosted jobs)
  labviewExe      = 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe'
}

$cfg = [ordered]@{
  detectLeaks     = Get-Bool $env:DETECT_LEAKS     $defaults.detectLeaks
  cleanAfter      = Get-Bool $env:CLEAN_AFTER      $defaults.cleanAfter
  unblockGuard    = Get-Bool $env:UNBLOCK_GUARD    $defaults.unblockGuard
  suppressUi      = Get-Bool $env:LV_SUPPRESS_UI   $defaults.suppressUi
  watchConsole    = Get-Bool $env:WATCH_CONSOLE    $defaults.watchConsole
  invokerRequired = Get-Bool $env:INVOKER_REQUIRED $defaults.invokerRequired
  labviewExe      = if ($env:LABVIEW_EXE) { $env:LABVIEW_EXE } else { $defaults.labviewExe }
}

if ($Json) {
  $cfg | ConvertTo-Json -Depth 4 | Write-Output
} else {
  [pscustomobject]$cfg | Write-Output
}
