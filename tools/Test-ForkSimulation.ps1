#Requires -Version 7.0
<#
.SYNOPSIS
Simulates a fork contributor workflow by staging a deterministic VI change,
opening a draft PR from the fork, and verifying the Vi Compare (Fork PR)
workflow completes successfully.

.DESCRIPTION
Creates a disposable branch off the requested base (defaults to develop),
copies a known fixture pair to guarantee a VI diff, pushes the branch to the
current fork (origin), opens a draft pull request targeting upstream/develop,
waits for the `VI Compare (Fork PR)` workflow to complete, and optionally
cleans up everything when the run succeeds.

.PARAMETER BaseBranch
Branch to branch from (defaults to develop). The script resets the local copy
to match upstream/<BaseBranch> before creating the scratch branch.

.PARAMETER KeepBranch
Skip cleanup so the branch and draft PR remain available for inspection.

.PARAMETER DryRun
Emit the actions that would be taken without performing any git/gh mutations.
#>
[CmdletBinding()]
param(
    [string]$BaseBranch = 'develop',
    [switch]$KeepBranch,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$IgnoreErrors
    )
    if ($DryRun) {
        Write-Host "[dry-run] git $($Arguments -join ' ')"
        return @()
    }

    $output = git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $IgnoreErrors) {
        throw "git $($Arguments -join ' ') failed:`n$output"
    }
    return @($output -split "`r?`n" | Where-Object { $_ -ne '' })
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$ExpectJson,
        [switch]$IgnoreErrors
    )
    if ($DryRun) {
        Write-Host "[dry-run] gh $($Arguments -join ' ')"
        return $null
    }

    $output = gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $IgnoreErrors) {
        throw "gh $($Arguments -join ' ') failed:`n$output"
    }
    if ($ExpectJson) {
        if (-not $output) { return $null }
        return $output | ConvertFrom-Json
    }
    return $output
}

function Ensure-GitClean {
    $statusRaw = Invoke-Git -Arguments @('status', '--porcelain')
    $status = @()
    if ($statusRaw) {
        if ($statusRaw -is [System.Array]) {
            $status = $statusRaw
        } else {
            $status = @($statusRaw)
        }

    }
    $status = @($status | Where-Object { $_ -and $_.Trim() -ne '' })

    if ($status.Count -gt 0) {
        throw "Working tree is not clean:`n$($status -join [Environment]::NewLine)"
    }

}
function Get-RepositorySlug {
    if ($DryRun) {
        return 'LabVIEW-Community-CI-CD/compare-vi-cli-action'
    }
    $slugOutput = Invoke-Git -Arguments @('remote', 'get-url', 'upstream')
    $slugArray = if ($slugOutput -is [System.Array]) { $slugOutput } elseif ($slugOutput) { @($slugOutput) } else { @() }
    $slug = if ($slugArray.Count -gt 0) { $slugArray[0] } else { $null }
    $pattern = '(?<=github\.com[:/])([^/]+/[^/]+?)(?:\.git)?$'
    $match = [regex]::Match($slug, $pattern)
    if (-not $match.Success) {
        throw 'Unable to determine upstream repository slug.'
    }
    return $match.Groups[1].Value
}

function Copy-FixturePair {
    param(
        [Parameter(Mandatory)][string]$SourceBase,
        [Parameter(Mandatory)][string]$SourceHead,
        [Parameter(Mandatory)][string]$TargetBase,
        [Parameter(Mandatory)][string]$TargetHead
    )
    if ($DryRun) {
        Write-Host "[dry-run] Copy $SourceBase -> $TargetBase"
        Write-Host "[dry-run] Copy $SourceHead -> $TargetHead"
        return
    }
    [System.IO.File]::Copy($SourceBase, $TargetBase, $true)
    [System.IO.File]::Copy($SourceHead, $TargetHead, $true)
}

function Wait-WorkflowCompletion {
    param(
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$Branch,
        [int]$TimeoutMinutes = 15
    )

    if ($DryRun) {
        Write-Host "[dry-run] Would wait for workflow '$WorkflowName' on branch '$Branch'"
        return
    }

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ($true) {
        $runs = Invoke-Gh -Arguments @(
            'run', 'list',
            '--workflow', $WorkflowName,
            '--branch', $Branch,
            '--json', 'databaseId,status,conclusion,headBranch,htmlUrl',
            '--limit', '5'
        ) -ExpectJson

        $match = $runs | Where-Object { $_.headBranch -eq $Branch } | Select-Object -First 1
        if ($match) {
            if ($match.status -eq 'completed') {
                if ($match.conclusion -ne 'success') {
                    throw "Workflow '$WorkflowName' failed (conclusion=$($match.conclusion)). See $($match.htmlUrl)"
                }
                Write-Host "Workflow '$WorkflowName' succeeded. See: $($match.htmlUrl)"
                return
            }
        }

        if ((Get-Date) -ge $deadline) {
            throw "Workflow '$WorkflowName' did not finish within $TimeoutMinutes minute(s)."
        }
        Start-Sleep -Seconds 10
    }
}

Ensure-GitClean

if ($DryRun) {
    $repoRoot = (Get-Location).Path
} else {
    $repoRoot = Invoke-Git -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1
    if (-not $repoRoot) {
        throw 'Unable to resolve repository root.'
    }
    $repoRoot = [System.IO.Path]::GetFullPath($repoRoot.Trim())
    Set-Location -LiteralPath $repoRoot
}

$upstreamSlug = Get-RepositorySlug
$forkRemote = 'origin'

Invoke-Git -Arguments @('fetch', 'upstream')
Invoke-Git -Arguments @('checkout', $BaseBranch)
Invoke-Git -Arguments @('reset', '--hard', "upstream/$BaseBranch")

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss')
$scratchBranch = "fork-sim/$timestamp"
$originalBranch = Invoke-Git -Arguments @('branch', '--show-current')

Invoke-Git -Arguments @('checkout', '-B', $scratchBranch)

$targetBaseVi = Join-Path 'fixtures' 'vi-attr' 'Base.vi'
$targetHeadVi = Join-Path 'fixtures' 'vi-attr' 'Head.vi'

$sourceBaseVi = Join-Path 'fixtures' 'vi-stage' 'bd-cosmetic' 'Base.vi'
$sourceHeadVi = Join-Path 'fixtures' 'vi-stage' 'bd-cosmetic' 'Head.vi'

Copy-FixturePair -SourceBase $sourceBaseVi -SourceHead $sourceHeadVi -TargetBase $targetBaseVi -TargetHead $targetHeadVi

Invoke-Git -Arguments @('add', $targetBaseVi, $targetHeadVi)
Invoke-Git -Arguments @('commit', '-m', "Fork simulation: BD cosmetic diff fixture ($timestamp)")

if (-not $DryRun) {
    Invoke-Git -Arguments @('push', '--set-upstream', $forkRemote, $scratchBranch)
}

$prNumber = $null
if (-not $DryRun) {
    $prPayload = Invoke-Gh -ExpectJson -Arguments @(
        'pr', 'create',
        '--base', $BaseBranch,
        '--head', "$($upstreamSlug.Split('/')[0]):$scratchBranch",
        '--title', "[fork-sim] VI diff smoke ($timestamp)",
        '--body', "Automated fork simulation to exercise **VI Compare (Fork PR)**.",
        '--draft'
    )
    $prNumber = $prPayload.number
    Write-Host "Opened draft PR #$prNumber ($($prPayload.url))"
}

try {
    Wait-WorkflowCompletion -WorkflowName 'VI Compare (Fork PR)' -Branch $scratchBranch
}
finally {
    if (-not $KeepBranch) {
        if ($prNumber -and -not $DryRun) {
            Invoke-Gh -Arguments @('pr', 'close', $prNumber.ToString(), '--delete-branch') -IgnoreErrors
        }
        Invoke-Git -Arguments @('checkout', $BaseBranch) | Out-Null
        if (-not $DryRun) {
            Invoke-Git -Arguments @('push', $forkRemote, '--delete', $scratchBranch) -IgnoreErrors
        }
        Invoke-Git -Arguments @('branch', '-D', $scratchBranch) -IgnoreErrors | Out-Null
    } else {
        Invoke-Git -Arguments @('checkout', $originalBranch) | Out-Null
    }
}

Write-Host 'Fork simulation helper completed.'
