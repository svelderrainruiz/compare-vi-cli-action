#Requires -Version 7.0
[CmdletBinding()]
param(
  [string]$RepositoryRoot = '.',
  [switch]$AutoCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
  param(
    [Parameter(Mandatory)] [string[]]$Args,
    [string]$WorkDir = $RepositoryRoot
  )
  Push-Location $WorkDir
  try {
    $out = & git @Args 2>&1
    [pscustomobject]@{ Code=$LASTEXITCODE; Out=$out }
  } finally { Pop-Location }
}

function Read-StandingIssueNumber {
  param([string]$Root)
  $cache = Join-Path $Root '.agent_priority_cache.json'
  if (Test-Path -LiteralPath $cache -PathType Leaf) {
    try { return ((Get-Content -Raw -LiteralPath $cache | ConvertFrom-Json).number) } catch {}
  }
  $branch = (Invoke-Git -Args @('rev-parse','--abbrev-ref','HEAD')).Out | Select-Object -First 1
  if ($branch -match '(?i)(issue|feat|fix|chore)/(\d+)') { return [int]$Matches[2] }
  return $null
}

function Ensure-AgentDirs {
  param([string]$Root)
  $dir = Join-Path $Root 'tests/results/_agent'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$agentDir = Ensure-AgentDirs -Root $root
$planPath = Join-Path $agentDir 'commit-plan.json'

# Detect changes
$status = Invoke-Git -Args @('status','--porcelain') -WorkDir $root
$changed = @($status.Out | Where-Object { $_ })

# Auto-stage: include all, then unstage volatile paths
if ($changed.Count -gt 0) {
  [void](Invoke-Git -Args @('add','-A') -WorkDir $root)
  # Unstage volatile files
  $volatile = @(
    '.agent_priority_cache.json',
    'tests/results',
    'tests\\results'
  )
  foreach ($pat in $volatile) {
    [void](Invoke-Git -Args @('restore','--staged','--worktree','--',$pat) -WorkDir $root)
  }
}

# Re-check staged set
$diffIndex = Invoke-Git -Args @('diff','--cached','--name-only') -WorkDir $root
$stagedFiles = @($diffIndex.Out | Where-Object { $_ })

$issueNum = Read-StandingIssueNumber -Root $root
$subject = if ($issueNum) { "chore(#$issueNum): standing priority update" } else { 'chore: standing priority update' }

$plan = [ordered]@{
  schema = 'agent-commit-plan/v1'
  generatedAt = (Get-Date).ToString('o')
  issue = $issueNum
  branch = (Invoke-Git -Args @('rev-parse','--abbrev-ref','HEAD')).Out | Select-Object -First 1
  staged = $stagedFiles
  autoSkipped = @('.agent_priority_cache.json','tests/results/**')
  suggestedMessage = $subject
  commitType = 'chore'
  commitDescription = 'standing priority update'
  autoCommitted = $false
  labels = @('standing priority update')
  tests = [ordered]@{ decision = if ($stagedFiles.Count -gt 0) { 'required' } else { 'skip' } }
  commitMessageStatus = [ordered]@{ needsEdit = $false; state = if ($stagedFiles.Count -gt 0) { 'ready' } else { 'no-staged-files' } }
}

if ($AutoCommit -and $stagedFiles.Count -gt 0) {
  $res = Invoke-Git -Args @('commit','-m',$subject) -WorkDir $root
  if ($res.Code -eq 0) { $plan.autoCommitted = $true }
}

$plan | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $planPath -Encoding utf8
Write-Host ("Prepare-StandingCommit: plan written to {0}" -f $planPath)

