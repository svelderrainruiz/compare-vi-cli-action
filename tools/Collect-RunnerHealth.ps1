[CmdletBinding()]
param(
  [string]$Enterprise = '',
  [string]$Repo,
  [string]$ServiceName = 'actions.runner.enterprises-labview-community-ci-cd.research',
  [string]$ResultsDir = 'tests/results',
  [switch]$AppendSummary,
  [switch]$EmitJson,
  [switch]$IncludeGhApi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Try-GetCommand {
  param([string]$Name)
  try { return (Get-Command -Name $Name -ErrorAction Stop) } catch { return $null }
}

function Get-RepoSlug {
  if ($Repo) { return $Repo }
  try {
    $url = (& git remote get-url origin 2>$null).Trim()
    if ($url -match 'github.com[:/](.+?)(\.git)?$') { return $Matches[1] }
  } catch {}
  return $null
}

$now = Get-Date
$osInfo = $PSVersionTable.OS
$psv = $PSVersionTable.PSVersion.ToString()
$repoSlug = Get-RepoSlug
$workRoot = (Resolve-Path .).Path
$drive = $null
try { $drive = Get-PSDrive -Name ($workRoot.Substring(0,1)) -ErrorAction SilentlyContinue } catch {}

# Service probe (Windows and Linux)
$service = $null
if ($IsWindows) {
  $svcObj = $null; $svcCim = $null
  try { $svcObj = Get-Service -Name $ServiceName -ErrorAction Stop } catch {}
  try { $svcCim = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop } catch {}
  if ($svcObj -or $svcCim) {
    $service = [ordered]@{
      name      = $ServiceName
      found     = $true
      status    = $svcObj.Status.ToString()
      startType = $svcCim.StartMode
      account   = $svcCim.StartName
      path      = $svcCim.PathName
    }
  } else {
    $service = @{ name = $ServiceName; found = $false }
  }
} else {
  # Linux systemd best-effort
  $systemctl = Try-GetCommand systemctl
  if ($systemctl) {
    try {
      $status = & $systemctl.Source show -p Id -p ActiveState -p FragmentPath "$ServiceName" 2>$null
      if ($LASTEXITCODE -eq 0 -and $status) {
        $kv = @{}
        foreach ($line in ($status -split "`n")) { if ($line -match '^(\w+?)=(.*)$') { $kv[$Matches[1]] = $Matches[2] } }
        $service = @{ name = $ServiceName; found = $true; active = $kv['ActiveState']; path = $kv['FragmentPath'] }
      } else { $service = @{ name = $ServiceName; found = $false } }
    } catch { $service = @{ name = $ServiceName; found = $false } }
  } else { $service = @{ name = $ServiceName; found = $false } }
}

# Queue snapshot via gh (optional)
$queue = @{}
if ($IncludeGhApi) {
  $gh = Try-GetCommand gh
  if ($gh -and $repoSlug) {
    try {
      $wfRunsRaw = & $gh.Source api "repos/$repoSlug/actions/workflows/ci-orchestrated.yml/runs?per_page=15" 2>$null
      $wfRuns = $wfRunsRaw | ConvertFrom-Json
      $queue.repo = [ordered]@{
        total   = $wfRuns.total_count
        queued  = ($wfRuns.workflow_runs | Where-Object { $_.status -eq 'queued' }).Count
        running = ($wfRuns.workflow_runs | Where-Object { $_.status -eq 'in_progress' }).Count
      }
    } catch { $queue.repo_error = $_.Exception.Message }
    if ($Enterprise) {
      try {
        $runnersRaw = & $gh.Source api "enterprises/$Enterprise/actions/runners?per_page=100" 2>$null
        $runners = $runnersRaw | ConvertFrom-Json
        $queue.enterprise = [ordered]@{
          online = ($runners.runners | Where-Object { $_.status -eq 'online' }).Count
          busy   = ($runners.runners | Where-Object { $_.busy }).Count
        }
      } catch { $queue.enterprise_error = $_.Exception.Message }
    }
  } else { $queue.repo_error = 'gh unavailable or repo slug missing' }
}

# Processes snapshot (best effort)
$procs = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in 'pwsh','LVCompare','LabVIEW' } |
  Select-Object Name,Id,StartTime,CPU,MainWindowTitle

$health = [ordered]@{
  schema      = 'runner-health/v1'
  generatedAt = $now.ToString('o')
  env         = @{ os = $osInfo; ps = $psv; repo = $repoSlug; workspace = $workRoot }
  workspace   = @{ diskFreeGB = if ($drive) { [math]::Round($drive.Free/1GB,2) } else { $null } }
  service     = $service
  queue       = $queue
  processes   = $procs
}

if ($EmitJson) {
  $outDir = Join-Path $ResultsDir '_agent'
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  ($health | ConvertTo-Json -Depth 6) | Out-File -FilePath (Join-Path $outDir 'runner-health.json') -Encoding utf8
}

if ($AppendSummary -and $env:GITHUB_STEP_SUMMARY) {
  $lines = @(
    '### Runner Health'
    "- Service: $($health.service.name) (found=$($health.service.found))"
  )

  $serviceStatusProp = $null
  if ($health.service) {
    $serviceStatusProp = $health.service.PSObject.Properties['status']
  }
  if ($serviceStatusProp) {
    $serviceStatus = $serviceStatusProp.Value
    if ($serviceStatus) {
      $lines += "- Service Status: $serviceStatus"
    }
  }

  $lines += @(
    "- OS/PS: $($osInfo) / PS $($psv)"
    "- Disk free: $($health.workspace.diskFreeGB) GB"
  )

  $queueRepoProp = $null
  if ($health.queue) {
    $queueRepoProp = $health.queue.PSObject.Properties['repo']
  }
  if ($queueRepoProp -and $queueRepoProp.Value) {
    $repoQueue = $queueRepoProp.Value
    $queuedProp = $repoQueue.PSObject.Properties['queued']
    $runningProp = $repoQueue.PSObject.Properties['running']
    $queuedVal = if ($queuedProp) { $queuedProp.Value } else { 'n/a' }
    $runningVal = if ($runningProp) { $runningProp.Value } else { 'n/a' }
    $lines += "- Orchestrated queued: $queuedVal; running: $runningVal"
  }

  $lines += "- Processes (pwsh/LVCompare/LabVIEW): $($procs.Count)"

  ($lines -join "`n") | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

exit 0
