#Requires -Version 7.0
[CmdletBinding()]
param(
  [string]$RepositoryRoot = '.',
  [switch]$Push,
  [switch]$CreatePR
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

function Ensure-AgentDirs {
  param([string]$Root)
  $dir = Join-Path $Root 'tests/results/_agent'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

function Ensure-Gh {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
  return $true
}

$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$agentDir = Ensure-AgentDirs -Root $root
$postPath = Join-Path $agentDir 'post-commit.json'

$branch = (Invoke-Git -Args @('rev-parse','--abbrev-ref','HEAD')).Out | Select-Object -First 1
$remote = 'origin'

$result = [ordered]@{
  schema = 'post-commit/actions@v1'
  generatedAt = (Get-Date).ToString('o')
  repoRoot = $root
  branch = $branch
  pushExecuted = $false
  pushResult = $null
  createPR = [bool]$CreatePR
  prResult = $null
}

if ($Push) {
  $pushRes = Invoke-Git -Args @('push','-u',$remote,$branch)
  $result.pushExecuted = $true
  $result.pushResult = [ordered]@{ ExitCode=$pushRes.Code; Output=@($pushRes.Out) }
}

if ($CreatePR) {
  if (Ensure-Gh) {
    $prArgs = @('pr','create','--fill','--base','develop')
    $prOut = & gh @prArgs 2>&1
    $result.prResult = [ordered]@{ created=($LASTEXITCODE -eq 0); output=@($prOut) }
  } else {
    $result.prResult = [ordered]@{ created=$false; output=@('gh CLI not available') }
  }
}

$result | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $postPath -Encoding utf8
Write-Host ("After-CommitActions: summary written to {0}" -f $postPath)

