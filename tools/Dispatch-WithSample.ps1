<#
.SYNOPSIS
  Dispatch a workflow with a freshly-generated sample_id.
.PARAMETER Workflow
  Workflow file (e.g., ci-orchestrated.yml) or workflow name.
.PARAMETER Ref
  Branch or ref to run against (default: develop).
.PARAMETER IncludeIntegration
  Optional 'true'/'false' to set include_integration input.
.PARAMETER ExtraInput
  Additional -f name=value pairs (array of strings) to pass to gh workflow run.
.NOTES
  Requires GitHub CLI (gh) authenticated with repo: actions permissions.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Workflow,
  [string]$Ref = 'develop',
  [ValidateSet('true','false')][string]$IncludeIntegration,
  [ValidateSet('single','matrix')][string]$Strategy = 'single',
  [string[]]$ExtraInput,
  [int]$WaitSeconds = 8
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Gh() { if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'gh CLI not found. Install GitHub CLI.' } }

Assert-Gh
$sid = & (Join-Path $PSScriptRoot 'New-SampleId.ps1')

# Resolve repo via gh (most reliable)
$repo = $null
try { $repo = (gh repo view --json nameWithOwner --jq .nameWithOwner) } catch {}
if (-not $repo) {
  $repo = $env:GITHUB_REPOSITORY
}
if (-not $repo) {
  try { $url = git remote get-url origin 2>$null; if ($url -match 'github\.com[:/](.+?/.+?)(?:\.git)?$') { $repo = $Matches[1] } } catch {}
}
if (-not $repo) { throw 'Unable to determine repository. Set GITHUB_REPOSITORY or ensure gh is authenticated.' }

# Resolve workflow id for robust dispatch
$wfId = $null
$workflowKey = $Workflow
if ($workflowKey -match '\.ya?ml$') {
  try { $workflowKey = Split-Path -Path $workflowKey -Leaf } catch {}
}
try {
  $wfIdCandidate = gh api "repos/$repo/actions/workflows/$workflowKey" --jq .id 2>$null
  if ($wfIdCandidate) { $wfId = $wfIdCandidate.ToString().Trim() }
} catch { $wfId = $null }
if (-not $wfId) {
  try {
    $listJson = gh workflow list -R $repo --json name,path,id
    $list = $null; try { $list = $listJson | ConvertFrom-Json -ErrorAction Stop } catch {}
    if ($list) {
      foreach ($wf in $list) {
        if (-not $wfId -and $wf.name -and $wf.name.Equals($Workflow, [System.StringComparison]::OrdinalIgnoreCase)) {
          $wfId = $wf.id
          break
        }
        if (-not $wfId -and $wf.path) {
          $pathLeaf = $null
          try { $pathLeaf = Split-Path -Path $wf.path -Leaf } catch {}
          if ($pathLeaf) {
            if ($pathLeaf.Equals($Workflow, [System.StringComparison]::OrdinalIgnoreCase)) {
              $wfId = $wf.id
              break
            }
            if ($Workflow -match '\.ya?ml$') {
              $targetLeaf = $workflowKey
              if ($pathLeaf.Equals($targetLeaf, [System.StringComparison]::OrdinalIgnoreCase)) {
                $wfId = $wf.id
                break
              }
            }
          }
        }
      }
    }
  } catch {}
}
if (-not $wfId) { $wfId = $Workflow }

$cmd = @('workflow','run', $wfId, '-R', $repo, '-r', $Ref, '-f', "sample_id=$sid")
if ($IncludeIntegration) { $cmd += @('-f', "include_integration=$IncludeIntegration") }
if ($Strategy) { $cmd += @('-f', "strategy=$Strategy") }
if ($ExtraInput) { foreach ($kv in $ExtraInput) { $cmd += @('-f', $kv) } }

Write-Host "Dispatching: gh $($cmd -join ' ')"
try {
  gh @cmd | Out-Null
} catch {
  Write-Host "gh workflow run failed, attempting REST dispatch via gh api..." -ForegroundColor Yellow
  $apiPath = "repos/$repo/actions/workflows/$wfId/dispatches"
  $form = @('-X','POST','-H','Accept: application/vnd.github+json','-F',("ref={0}" -f $Ref),'-F',("inputs[sample_id]={0}" -f $sid))
  if ($IncludeIntegration) { $form += @('-F', ("inputs[include_integration]={0}" -f $IncludeIntegration)) }
  if ($Strategy) { $form += @('-F', ("inputs[strategy]={0}" -f $Strategy)) }
  gh api $apiPath @form | Out-Null
}
Write-Host "Dispatched with sample_id=$sid"

# Brief wait and list recent runs to confirm presence
if ($WaitSeconds -gt 0) { Start-Sleep -Seconds $WaitSeconds }
Write-Host 'Recent runs (last 15):'
gh run list -R $repo -L 15 | Out-Host
Write-Host 'If not visible yet, it may take a few seconds to appear.'
