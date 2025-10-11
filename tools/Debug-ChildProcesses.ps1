<#
.SYNOPSIS
  Capture a snapshot of child processes (pwsh, conhost, LabVIEW, LVCompare) with memory usage.

.DESCRIPTION
  Writes a JSON snapshot to tests/results/_agent/child-procs.json and optionally appends
  a brief summary to the GitHub Step Summary when available.
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'tests/results',
  [string[]]$Names = @('pwsh','conhost','LabVIEW','LVCompare','g-cli','VIPM'),
  [switch]$AppendStepSummary
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CommandLine([int]$Pid){
  try { ($ci = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $Pid) -ErrorAction SilentlyContinue); return ($ci.CommandLine) } catch { return $null }
}

$repoRoot = (Resolve-Path '.').Path
$agentDir = Join-Path $repoRoot (Join-Path $ResultsDir '_agent')
if (-not (Test-Path -LiteralPath $agentDir)) { New-Item -ItemType Directory -Path $agentDir -Force | Out-Null }
$outPath = Join-Path $agentDir 'child-procs.json'

$snapshot = [ordered]@{
  schema = 'child-procs-snapshot/v1'
  at     = (Get-Date).ToUniversalTime().ToString('o')
  groups = @{}
}

$summaryLines = @('### Child Processes Snapshot','')
foreach ($name in $Names) {
  $procs = @()
  try {
    if ($name -ieq 'g-cli') {
      $procs = @(Get-CimInstance Win32_Process -Filter "Name='g-cli.exe'" -ErrorAction SilentlyContinue)
    } elseif ($name -ieq 'VIPM') {
      $procs = @(Get-Process -Name 'VIPM' -ErrorAction SilentlyContinue)
      if (-not $procs -or $procs.Count -eq 0) {
        # Fallback via CIM (in case of session/bitness differences)
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='VIPM.exe'" -ErrorAction SilentlyContinue)
      }
    } else {
      $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
  } catch { $procs = @() }
  $items = @()
  $totalWs = 0L; $totalPm = 0L
  foreach ($p in $procs) {
    $title = $null
    try { $title = $p.MainWindowTitle } catch {}
    $pid = try { [int]$p.Id } catch { try { [int]$p.ProcessId } catch { $null } }
    $cmd = if ($pid) { Get-CommandLine -Pid $pid } else { $null }
    $ws = 0L; $pm = 0L
    try { $ws = [int64]$p.WorkingSet64 } catch {}
    try { $pm = [int64]$p.PagedMemorySize64 } catch {}
    $totalWs += $ws; $totalPm += $pm
    $items += [pscustomobject]@{
      pid   = $pid
      ws    = $ws
      pm    = $pm
      title = $title
      cmd   = $cmd
    }
  }
  $snapshot.groups[$name] = [pscustomobject]@{
    count  = $procs.Count
    memory = @{ ws = $totalWs; pm = $totalPm }
    items  = $items
  }
  $summaryLines += ('- {0}: count={1}, wsMB={2:N1}, pmMB={3:N1}' -f $name, $procs.Count, ($totalWs/1MB), ($totalPm/1MB))
}

$snapshot | ConvertTo-Json -Depth 6 | Out-File -FilePath $outPath -Encoding utf8

if ($AppendStepSummary -and $env:GITHUB_STEP_SUMMARY) {
  try { ($summaryLines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8 } catch {}
}

Write-Host ("Child process snapshot written: {0}" -f $outPath) -ForegroundColor DarkGray
$snapshot
