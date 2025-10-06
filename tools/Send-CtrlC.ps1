#Requires -Version 7.0
<#!
.SYNOPSIS
  Attempt to send Ctrl+C (and Ctrl+Break) to target console processes to unblock hangs.
.PARAMETER Pid
  One or more process Ids to target.
.PARAMETER Names
  One or more process names to target (e.g., 'pwsh','conhost').
.PARAMETER Max
  Maximum number of processes per name to target (default 5).
.PARAMETER DryRun
  List targets without sending events.
#>
param(
  [int[]]$Pid,
  [string[]]$Names,
  [int]$Max = 5,
  [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -Namespace Win32 -Name ConsoleCtrl -MemberDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AttachConsole(uint dwProcessId);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeConsole();
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleCtrlHandler(ConsoleCtrlDelegate HandlerRoutine, bool Add);
  public delegate bool ConsoleCtrlDelegate(uint CtrlType);
}
"@

function Send-CtrlEvent([int]$targetPid){
  try {
    [Win32.ConsoleCtrl.NativeMethods]::FreeConsole() | Out-Null
    # Ignore Ctrl+C in this process when generating the event
    [Win32.ConsoleCtrl.NativeMethods]::SetConsoleCtrlHandler($null, $true) | Out-Null
    if (-not [Win32.ConsoleCtrl.NativeMethods]::AttachConsole([uint32]$targetPid)) { return $false }
    # 0 = CTRL_C_EVENT, 1 = CTRL_BREAK_EVENT
    $ok = [Win32.ConsoleCtrl.NativeMethods]::GenerateConsoleCtrlEvent(0, 0)
    Start-Sleep -Milliseconds 200
    if (-not $ok) { $ok = [Win32.ConsoleCtrl.NativeMethods]::GenerateConsoleCtrlEvent(1, 0) }
    [Win32.ConsoleCtrl.NativeMethods]::FreeConsole() | Out-Null
    [Win32.ConsoleCtrl.NativeMethods]::SetConsoleCtrlHandler($null, $false) | Out-Null
    return $ok
  } catch { return $false }
}

$targets = @()
if ($Pid) { $targets += $Pid }
if ($Names) {
  foreach($n in $Names){
    $procs = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First $Max
    if ($procs) { $targets += ($procs | Select-Object -ExpandProperty Id) }
  }
}
$targets = $targets | Sort-Object -Unique
if (-not $targets -or $targets.Count -eq 0) { Write-Host 'No targets found.'; exit 0 }

Write-Host ("Targets: {0}" -f ($targets -join ','))
if ($DryRun) { exit 0 }

$sent = 0
foreach($t in $targets){ if (Send-CtrlEvent $t) { $sent++ } }
Write-Host ("Ctrl events sent: {0}/{1}" -f $sent,$targets.Count)
if ($sent -lt $targets.Count) { Write-Host 'Some targets did not accept Ctrl events; consider Stop-Process as fallback.' }

