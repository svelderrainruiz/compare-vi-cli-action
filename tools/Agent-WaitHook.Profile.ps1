Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Agent-Wait.ps1')

if (-not (Get-Variable -Name __AgentWaitHook -Scope Global -ErrorAction SilentlyContinue)) {
  Set-Variable -Name __AgentWaitHook -Scope Global -Value ([pscustomobject]@{ Enabled=$false; ResultsDir='tests/results'; SavedPrompt=$null; Id='default' }) -Force
}

function Enable-AgentWaitHook {
  [CmdletBinding()] param(
    [string]$Reason = 'unspecified',
    [int]$ExpectedSeconds = 90,
    [int]$ToleranceSeconds = 5,
    [string]$ResultsDir = 'tests/results',
    [string]$Id = 'default'
  )
  $state = $global:__AgentWaitHook
  if (-not $state.SavedPrompt) {
    try { $state.SavedPrompt = (Get-Command Prompt -ErrorAction SilentlyContinue).ScriptBlock } catch { $state.SavedPrompt = $null }
  }
  Start-AgentWait -Reason $Reason -ExpectedSeconds $ExpectedSeconds -ResultsDir $ResultsDir -ToleranceSeconds $ToleranceSeconds -Id $Id | Out-Null
  $state.Enabled = $true
  $state.ResultsDir = $ResultsDir
  $state.Id = $Id

  function global:Prompt {
    # Auto-end wait if marker exists and not yet ended for current startedUtc
    try {
      $root = $global:__AgentWaitHook.ResultsDir
      $dir = Join-Path $root '_agent'
      $sessionDir = Join-Path $dir (Join-Path 'sessions' $global:__AgentWaitHook.Id)
      $markerPath = Join-Path $sessionDir 'wait-marker.json'
      $lastPath = Join-Path $sessionDir 'wait-last.json'
      if ($global:__AgentWaitHook.Enabled -and (Test-Path $markerPath)) {
        $m = Get-Content $markerPath -Raw | ConvertFrom-Json
        $needEnd = $true
        if (Test-Path $lastPath) {
          $l = Get-Content $lastPath -Raw | ConvertFrom-Json
          if ($l.PSObject.Properties['startedUtc'] -and $l.PSObject.Properties['endedUtc']) {
            if ($l.startedUtc -eq $m.startedUtc) { $needEnd = $false }
          }
        }
        if ($needEnd) { End-AgentWait -ResultsDir $root -Id $global:__AgentWaitHook.Id | Out-Null }
      }
    } catch { }
    # Call saved/original prompt if present
    if ($global:__AgentWaitHook.SavedPrompt) { & $global:__AgentWaitHook.SavedPrompt } else { 'PS ' + (Get-Location) + '> ' }
  }
}

function Disable-AgentWaitHook {
  [CmdletBinding()] param()
  $state = $global:__AgentWaitHook
  $state.Enabled = $false
  if ($state.SavedPrompt) {
    # Restore original prompt
    Set-Item -Path Function:Prompt -Value $state.SavedPrompt -ErrorAction SilentlyContinue
  }
}

# Export only when running inside a module context
try {
  if ($PSVersionTable -and $ExecutionContext -and $ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Enable-AgentWaitHook, Disable-AgentWaitHook
  }
} catch {}
