#Requires -Version 7.0
<#
.SYNOPSIS
End-to-end smoke test for the PR VI history workflow.

.DESCRIPTION
Creates a disposable branch with a synthetic VI change, opens a draft PR,
dispatches `pr-vi-history.yml`, monitors the workflow to completion, and
verifies that the PR comment includes the history summary. By default the PR
and branch are deleted once the smoke run succeeds.

.PARAMETER BaseBranch
Branch to branch from when generating the synthetic history change. Defaults to
`develop`.

.PARAMETER KeepBranch
Skip cleanup so the scratch branch and draft PR remain available for inspection.

.PARAMETER DryRun
Emit the planned steps without executing them.

.PARAMETER Scenario
Selects which synthetic change set to exercise.
- `attribute`: legacy single-commit attr diff.
- `sequential`: one target VI, multi-commit fixture replay.
- `sequential-multi-vi`: two target VIs changed in each sequential commit.
- `signal-masscompile`: one real VI change and one masscompile-only VI change in the same commit.

.PARAMETER MaxPairs
Optional override for the `max_pairs` workflow input. Defaults to `6`.

.PARAMETER CompareBaseRef
Optional compare-window base ref passed to `pr-vi-history.yml` dispatch (`base_ref`).
Defaults to the smoke `BaseBranch`.

.PARAMETER CompareHeadRef
Optional compare-window head ref passed to `pr-vi-history.yml` dispatch (`head_ref`).
Defaults to the generated scratch branch.

.PARAMETER IncludeMergeParents
When present, dispatches `include_merge_parents=true` so merge-parent lineage is
included in history traversal.
#>
[CmdletBinding()]
param(
    [string]$BaseBranch = 'develop',
    [switch]$KeepBranch,
    [switch]$DryRun,
    [ValidateSet('attribute', 'sequential', 'sequential-multi-vi', 'signal-masscompile')]
    [string]$Scenario = 'attribute',
    [int]$MaxPairs = 6,
    [string]$CompareBaseRef,
    [string]$CompareHeadRef,
    [switch]$IncludeMergeParents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )
    $output = git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$output"
    }
    return @($output -split "`r?`n" | Where-Object { $_ -ne '' })
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$ExpectJson
    )
    $output = gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($Arguments -join ' ') failed:`n$output"
    }
    if ($ExpectJson) {
        if (-not $output) { return $null }
        return $output | ConvertFrom-Json
    }
    return $output
}

function Get-RepoInfo {
    if ($env:GITHUB_REPOSITORY -and ($env:GITHUB_REPOSITORY -match '^(?<owner>[^/]+)/(?<name>.+)$')) {
        return [ordered]@{
            Slug  = $env:GITHUB_REPOSITORY
            Owner = $Matches['owner']
            Name  = $Matches['name']
        }
    }
    $remote = Invoke-Git -Arguments @('remote', 'get-url', 'origin') | Select-Object -First 1
    if ($remote -match 'github.com[:/](?<owner>[^/]+)/(?<name>.+?)(?:\.git)?$') {
        return [ordered]@{
            Slug  = "$($Matches['owner'])/$($Matches['name'])"
            Owner = $Matches['owner']
            Name  = $Matches['name']
        }
    }
    throw 'Unable to determine repository slug.'
}

function Get-GitHubAuth {
    $token = $env:GH_TOKEN
    if (-not $token) {
        $token = $env:GITHUB_TOKEN
    }
    if (-not $token) {
        throw 'GH_TOKEN or GITHUB_TOKEN must be set.'
    }

    $headers = @{
        Authorization = "Bearer $token"
        Accept        = 'application/vnd.github+json'
        'User-Agent'  = 'compare-vi-history-smoke'
    }

    return [ordered]@{
        Token   = $token
        Headers = $headers
    }
}

function Get-PullRequestInfo {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Repo,
        [Parameter(Mandatory)]
        [string]$Branch,
        [int]$Attempts = 10,
        [int]$DelaySeconds = 2
    )

    $auth = Get-GitHubAuth
    $headers = $auth.Headers

    $lastError = $null
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        try {
            $uri = "https://api.github.com/repos/$($Repo.Slug)/pulls?head=$($Repo.Owner):$Branch&state=open"
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if ($response -and $response.Count -gt 0) {
                return $response[0]
            }
        } catch {
            $lastError = $_
        }
        if ($attempt -lt $Attempts - 1) {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    if ($lastError) {
        throw "Failed to locate scratch PR: $($lastError.Exception.Message)"
    }
    throw 'Failed to locate scratch PR.'
}

function Ensure-CleanWorkingTree {
    $status = @(Invoke-Git -Arguments @('status', '--porcelain'))
    if ($status.Count -eq 1 -and [string]::IsNullOrWhiteSpace($status[0])) {
        $status = @()
    }
    if ($status.Count -gt 0) {
        throw 'Working tree not clean. Commit or stash changes before running the smoke test.'
    }
}

function Copy-VIContent {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Source VI file not found: $Source"
    }

    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        throw "Destination directory not found: $destDir"
    }

    [System.IO.File]::Copy($Source, $Destination, $true)
}

function Get-ChangedWorkingTreePaths {
    $statusLines = @(Invoke-Git -Arguments @('status', '--porcelain'))
    if ($statusLines.Count -eq 1 -and [string]::IsNullOrWhiteSpace($statusLines[0])) {
        return @()
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($lineRaw in $statusLines) {
        if ([string]::IsNullOrWhiteSpace($lineRaw)) { continue }
        if ($lineRaw.Length -lt 4) { continue }
        $pathPart = $lineRaw.Substring(3).Trim()
        if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
        if ($pathPart -like '* -> *') {
            $pathPart = ($pathPart -split '\s+->\s+')[-1]
        }
        if (-not [string]::IsNullOrWhiteSpace($pathPart)) {
            $paths.Add($pathPart) | Out-Null
        }
    }

    return @($paths | Select-Object -Unique)
}

$script:HistoryTrackingFlags = [ordered]@{
    assume = $false
    skip   = $false
}
function Enable-HistoryTracking {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        $lsEntry = Invoke-Git -Arguments @('ls-files', '-v', $Path) | Select-Object -First 1
        if ($lsEntry) {
            $prefix = $lsEntry.Substring(0,1)
            if ($prefix -match '[Hh]') { $script:HistoryTrackingFlags.assume = $true }
            if ($prefix -match '[Ss]') { $script:HistoryTrackingFlags.skip = $true }
        }
    } catch {
        Write-Warning ("Failed to query tracking flags for {0}: {1}" -f $Path, $_.Exception.Message)
    }

    try {
        Invoke-Git -Arguments @('update-index', '--no-assume-unchanged', $Path) | Out-Null
        Invoke-Git -Arguments @('update-index', '--no-skip-worktree', $Path) | Out-Null
    } catch {
        Write-Warning ("Failed to adjust tracking flags for {0}: {1}" -f $Path, $_.Exception.Message)
    }
}

function Restore-HistoryTracking {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        if ($script:HistoryTrackingFlags.assume) {
            Invoke-Git -Arguments @('update-index', '--assume-unchanged', $Path) | Out-Null
        }
        if ($script:HistoryTrackingFlags.skip) {
            Invoke-Git -Arguments @('update-index', '--skip-worktree', $Path) | Out-Null
        }
    } catch {
        Write-Warning ("Failed to restore tracking flags for {0}: {1}" -f $Path, $_.Exception.Message)
    } finally {
        $script:HistoryTrackingFlags.assume = $false
        $script:HistoryTrackingFlags.skip = $false
    }
}


$script:SequentialFixtureCache = $null

function Get-SequentialHistorySequence {
    if ($script:SequentialFixtureCache) {
        return $script:SequentialFixtureCache
    }

    $repoRoot = Invoke-Git -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        throw 'Unable to resolve repository root for sequential history fixture.'
    }

    $fixturePath = Join-Path $repoRoot 'fixtures' 'vi-history' 'sequential.json'
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
        throw "Sequential history fixture not found: $fixturePath"
    }

    try {
        $fixtureRaw = Get-Content -LiteralPath $fixturePath -Raw -ErrorAction Stop
        $fixtureObj = $fixtureRaw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw ("Unable to parse sequential history fixture {0}: {1}" -f $fixturePath, $_.Exception.Message)
    }

    if ($fixtureObj.schema -ne 'vi-history-sequence@v1') {
        throw "Unsupported sequential fixture schema '$($fixtureObj.schema)' (expected vi-history-sequence@v1)."
    }

    if ([string]::IsNullOrWhiteSpace($fixtureObj.targetPath)) {
        throw 'Sequential history fixture must declare targetPath.'
    }

    if (-not $fixtureObj.steps -or $fixtureObj.steps.Count -eq 0) {
        throw 'Sequential history fixture must define at least one step.'
    }

    $targetResolved = if ([System.IO.Path]::IsPathRooted($fixtureObj.targetPath)) {
        $fixtureObj.targetPath
    } else {
        Join-Path $repoRoot $fixtureObj.targetPath
    }

    if (-not (Test-Path -LiteralPath $targetResolved -PathType Leaf)) {
        throw "Sequential history target not found on disk: $($fixtureObj.targetPath)"
    }

    $stepObjects = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($step in $fixtureObj.steps) {
        if (-not $step.source) {
            throw 'Sequential history fixture step missing source path.'
        }

        $resolvedSource = if ([System.IO.Path]::IsPathRooted($step.source)) {
            $step.source
        } else {
            Join-Path $repoRoot $step.source
        }

        if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
            throw "Sequential history source not found: $($step.source)"
        }

        $stepObjects.Add([pscustomobject]@{
            id             = $step.id
            title          = $step.title
            message        = $step.message
            source         = $step.source
            resolvedSource = $resolvedSource
        }) | Out-Null
    }

    $script:SequentialFixtureCache = [pscustomobject]@{
        path               = $fixturePath
        repoRoot           = $repoRoot
        targetPathRelative = $fixtureObj.targetPath
        targetPathResolved = $targetResolved
        steps              = $stepObjects
        maxPairs           = if ($fixtureObj.PSObject.Properties['maxPairs']) { [int]$fixtureObj.maxPairs } else { $null }
    }

    return $script:SequentialFixtureCache
}

function Invoke-AttributeHistoryCommit {
    param(
        [Parameter(Mandatory)]
        [string]$TargetVi
    )

    $candidateSources = @(
        'fixtures/vi-attr/Base.vi',
        'fixtures/vi-attr/attr/HeadAttr.vi',
        'fixtures/vi-stage/fp-cosmetic/Head.vi'
    )
    $selectedSource = $null
    foreach ($candidate in $candidateSources) {
        Write-Host "Applying synthetic history change candidate: $TargetVi <= $candidate"
        Copy-VIContent -Source $candidate -Destination $TargetVi
        $statusAfterCandidate = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $TargetVi))
        Write-Host ("Post-candidate status for {0}: {1}" -f $TargetVi, ($statusAfterCandidate -join ' '))
        if ($statusAfterCandidate.Count -gt 0) {
            $selectedSource = $candidate
            break
        }
    }

    if (-not $selectedSource) {
        throw 'Attribute scenario produced no target delta across all candidate fixture sources.'
    }

    Invoke-Git -Arguments @('add', '-f', $TargetVi) | Out-Null
    Invoke-Git -Arguments @('commit', '-m', 'chore: synthetic VI attr diff for history smoke') | Out-Null

    return @(
        [pscustomobject]@{
            Title   = 'VI Attribute'
            Source  = $selectedSource
            Message = 'chore: synthetic VI attr diff for history smoke'
        }
    )
}

function Invoke-SignalMassCompileHistoryCommit {
    param(
        [Parameter(Mandatory)]
        [string]$SignalTargetVi,
        [Parameter(Mandatory)]
        [string]$MassCompileTargetVi
    )

    $signalSource = 'fixtures/vi-stage/control-rename/Head.vi'
    Write-Host ("Applying signal change: {0} <= {1}" -f $SignalTargetVi, $signalSource)
    Copy-VIContent -Source $signalSource -Destination $SignalTargetVi
    $signalStatus = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $SignalTargetVi))
    if ($signalStatus.Count -eq 0) {
        throw ("Signal step produced no delta for target: {0}" -f $SignalTargetVi)
    }

    $repoRoot = Invoke-Git -Arguments @('rev-parse', '--show-toplevel') | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        throw 'Unable to resolve repository root for masscompile step.'
    }

    $massCompileTargetResolved = if ([System.IO.Path]::IsPathRooted($MassCompileTargetVi)) {
        $MassCompileTargetVi
    } else {
        Join-Path $repoRoot $MassCompileTargetVi
    }
    if (-not (Test-Path -LiteralPath $massCompileTargetResolved -PathType Leaf)) {
        throw ("Masscompile target not found: {0}" -f $MassCompileTargetVi)
    }

    $labviewCliModulePath = Join-Path $repoRoot 'tools' 'LabVIEWCli.psm1'
    if (-not (Test-Path -LiteralPath $labviewCliModulePath -PathType Leaf)) {
        throw ("LabVIEW CLI module not found: {0}" -f $labviewCliModulePath)
    }

    try {
        Import-Module -Name $labviewCliModulePath -Force -ErrorAction Stop
    } catch {
        throw ("Failed to import LabVIEW CLI module: {0}" -f $_.Exception.Message)
    }

    $massCompileLogPath = Join-Path $env:TEMP ("compare-vi-history-smoke-masscompile-{0}.log" -f (Get-Date).ToString('yyyyMMddHHmmss'))
    $massCompileLabVIEWPath = $null
    $massCompilePathOverrides = @(
        [System.Environment]::GetEnvironmentVariable('PR_VI_HISTORY_MASSCOMPILE_LABVIEW_PATH', 'Process'),
        [System.Environment]::GetEnvironmentVariable('LABVIEW_PATH', 'Process')
    )
    foreach ($override in $massCompilePathOverrides) {
        if ([string]::IsNullOrWhiteSpace($override)) { continue }
        $massCompileLabVIEWPath = $override.Trim()
        break
    }
    Write-Host ("Running LabVIEW masscompile on {0}" -f $MassCompileTargetVi)
    try {
        $massCompileParams = @{
            DirectoryToCompile = $massCompileTargetResolved
            MassCompileLogFile = $massCompileLogPath
            Provider           = 'auto'
        }
        if (-not [string]::IsNullOrWhiteSpace($massCompileLabVIEWPath)) {
            $massCompileParams['LabVIEWPath'] = $massCompileLabVIEWPath
            Write-Host ("Masscompile LabVIEWPath override: {0}" -f $massCompileLabVIEWPath)
        }
        $massCompileResult = Invoke-LVMassCompile `
            @massCompileParams `
            
    } catch {
        $massCompileError = $_.Exception.Message
        if (
            $massCompileError -match '(?i)Open/Create/Replace File' -and
            $massCompileError -match '(?i)LabVIEW\.ini'
        ) {
            $overrideHint = if ([string]::IsNullOrWhiteSpace($massCompileLabVIEWPath)) {
                'Set PR_VI_HISTORY_MASSCOMPILE_LABVIEW_PATH (or LABVIEW_PATH) to an explicit LabVIEW executable path (for example LabVIEW 2026) and retry.'
            } else {
                ("Current override: {0}" -f $massCompileLabVIEWPath)
            }
            throw ("Masscompile blocked by LabVIEW.ini write failure ({0}). {1}" -f $MassCompileTargetVi, $overrideHint)
        }
        throw ("Masscompile operation failed for {0}: {1}" -f $MassCompileTargetVi, $massCompileError)
    }

    if ($massCompileResult -and $massCompileResult.PSObject.Properties['exitCode']) {
        $massCompileExitCode = [int]$massCompileResult.exitCode
        if ($massCompileExitCode -ne 0) {
            throw ("Masscompile returned non-zero exit code {0} for target {1}." -f $massCompileExitCode, $MassCompileTargetVi)
        }
    }

    $massCompileStatus = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $MassCompileTargetVi))
    if ($massCompileStatus.Count -eq 0) {
        throw ("Masscompile completed but produced no tracked delta for {0}. Use a VI that rewrites on compile for this scenario." -f $MassCompileTargetVi)
    }

    $changedPaths = @(Get-ChangedWorkingTreePaths)
    if ($changedPaths.Count -eq 0) {
        throw 'Working tree has no modified paths after mixed signal+masscompile step.'
    }

    $nonViPaths = @($changedPaths | Where-Object { $_ -notlike '*.vi' })
    if ($nonViPaths.Count -gt 0) {
        throw ("Unexpected non-VI changes detected after masscompile step: {0}" -f ($nonViPaths -join ', '))
    }

    $changedViPaths = @($changedPaths | Where-Object { $_ -like '*.vi' } | Select-Object -Unique)
    if ($changedViPaths.Count -lt 2) {
        throw ("Expected at least two changed VI paths (signal + masscompile), but found: {0}" -f ($changedViPaths -join ', '))
    }

    $addArgs = @('add', '-f') + $changedViPaths
    Invoke-Git -Arguments $addArgs | Out-Null
    $commitMessage = 'chore: mixed signal + masscompile same-commit history step'
    Invoke-Git -Arguments @('commit', '-m', $commitMessage) | Out-Null

    return @(
        [pscustomobject]@{
            Title   = 'Signal + Masscompile (same commit)'
            Source  = "$signalSource + masscompile:$MassCompileTargetVi"
            Targets = $changedViPaths
            Message = $commitMessage
        }
    )
}

function Invoke-SequentialHistoryCommits {
    param(
        [Parameter(Mandatory)]
        [string[]]$TargetVi
    )

    $fixture = Get-SequentialHistorySequence
    Write-Verbose ("Sequential fixture loaded from {0}" -f $fixture.path)

    $targetSources = @()
    if ($TargetVi -and $TargetVi.Count -gt 0) {
        $targetSources = @($TargetVi | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($targetSources.Count -eq 0) {
        $targetSources = @($fixture.targetPathRelative)
    }

    $targets = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($targetSource in $targetSources) {
        $targetResolved = if ([System.IO.Path]::IsPathRooted($targetSource)) {
            $targetSource
        } else {
            Join-Path $fixture.repoRoot $targetSource
        }

        $targetRelative = if ([System.IO.Path]::IsPathRooted($targetSource)) {
            [System.IO.Path]::GetRelativePath($fixture.repoRoot, $targetResolved)
        } else {
            $targetSource
        }

        if (-not (Test-Path -LiteralPath $targetResolved -PathType Leaf)) {
            throw ("Sequential history target not found on disk: {0}" -f $targetSource)
        }

        if ($fixture.targetPathRelative -and ($fixture.targetPathRelative -ne $targetRelative)) {
            Write-Verbose ("Sequential fixture primary target differs from supplied target: fixture={0}, requested={1}" -f $fixture.targetPathRelative, $targetRelative)
        }

        $targets.Add([pscustomobject]@{
            relative = $targetRelative
            resolved = $targetResolved
        }) | Out-Null
    }

    $commits = New-Object System.Collections.Generic.List[pscustomobject]
    for ($index = 0; $index -lt $fixture.steps.Count; $index++) {
        $step = $fixture.steps[$index]
        $stepNumber = $index + 1
        $displaySource = if ($step.source) { $step.source } else { $step.resolvedSource }
        $changedTargets = New-Object System.Collections.Generic.List[string]

        foreach ($target in $targets) {
            Write-Host ("Applying sequential step {0}: {1} <= {2}" -f $stepNumber, $target.relative, $displaySource)
            Copy-VIContent -Source $step.resolvedSource -Destination $target.resolved
            $statusAfterStep = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $target.relative))
            Write-Host ("Post-step status for {0}: {1}" -f $target.relative, ($statusAfterStep -join ' '))
            if ($statusAfterStep.Count -gt 0) {
                $changedTargets.Add($target.relative) | Out-Null
            }
        }

        if ($changedTargets.Count -eq 0) {
            Write-Host ("Sequential step {0} produced no file delta; skipping commit." -f $stepNumber)
            continue
        }
        $addArgs = @('add', '-f') + @($changedTargets.ToArray())
        Invoke-Git -Arguments $addArgs | Out-Null
        $commitMessage = if ([string]::IsNullOrWhiteSpace($step.message)) {
            "chore: sequential history step $stepNumber"
        } else {
            $step.message
        }
        Invoke-Git -Arguments @('commit', '-m', $commitMessage) | Out-Null
        $commits.Add([pscustomobject]@{
            Title   = if ($step.title) { $step.title } else { "Step $stepNumber" }
            Source  = $displaySource
            Targets = @($changedTargets.ToArray())
            Message = $commitMessage
        }) | Out-Null
    }

    if ($commits.Count -lt 1) {
        throw 'Sequential history fixture produced no commits; every step resolved to a no-op for the target VI.'
    }

    return $commits.ToArray()
}

Write-Verbose "Base branch: $BaseBranch"
Write-Verbose "KeepBranch: $KeepBranch"
Write-Verbose "DryRun: $DryRun"
Write-Verbose "Scenario: $Scenario"
Write-Verbose "MaxPairs: $MaxPairs"
Write-Verbose "CompareBaseRef: $CompareBaseRef"
Write-Verbose "CompareHeadRef: $CompareHeadRef"
Write-Verbose "IncludeMergeParents: $IncludeMergeParents"

$repoInfo = Get-RepoInfo
$initialBranch = Invoke-Git -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') | Select-Object -First 1

Ensure-CleanWorkingTree

$scenarioKey = $Scenario.ToLowerInvariant()
$scenarioTargetMinDiffs = @{}
$scenarioDiffStatusRequiredTargets = @()
$scenarioRequireMobilePreview = $false
switch ($scenarioKey) {
    'attribute' {
        $scenarioBranchSuffix = 'attr'
        $scenarioDescription  = 'synthetic attribute difference'
        $scenarioExpectation  = '`/vi-history` workflow completes successfully'
        $scenarioPlanHint     = '- Replace fixtures/vi-attr/Head.vi with attribute variant and commit'
        $scenarioNeedsArtifactValidation = $false
        $scenarioTargetPaths = @('fixtures/vi-attr/Head.vi')
    }
    'sequential' {
        $scenarioBranchSuffix = 'sequential'
        $scenarioDescription  = 'sequential multi-category history'
        $scenarioExpectation  = '`/vi-history` workflow reports multi-row diff summary'
        $scenarioPlanHint     = '- Apply sequential fixture commits from fixtures/vi-history/sequential.json (attribute, front panel, connector pane, control rename, block diagram cosmetic)'
        $scenarioNeedsArtifactValidation = $true
        $scenarioTargetPaths = @('fixtures/vi-attr/Head.vi')
        $scenarioTargetMinDiffs = @{ 'fixtures/vi-attr/Head.vi' = 1 }
        $scenarioDiffStatusRequiredTargets = @('fixtures/vi-attr/Head.vi')
        $scenarioRequireMobilePreview = $true
    }
    'sequential-multi-vi' {
        $scenarioBranchSuffix = 'sequential-multi-vi'
        $scenarioDescription  = 'sequential multi-category history (two VIs per commit)'
        $scenarioExpectation  = '`/vi-history` workflow reports per-target rows for two sequentially changed VIs'
        $scenarioPlanHint     = '- Apply sequential fixture commits to fixtures/vi-attr/Head.vi and fixtures/vi-attr/Base.vi in each commit'
        $scenarioNeedsArtifactValidation = $true
        $scenarioTargetPaths = @('fixtures/vi-attr/Head.vi', 'fixtures/vi-attr/Base.vi')
        $scenarioTargetMinDiffs = @{
            'fixtures/vi-attr/Head.vi' = 1
            'fixtures/vi-attr/Base.vi' = 1
        }
        $scenarioDiffStatusRequiredTargets = @('fixtures/vi-attr/Head.vi', 'fixtures/vi-attr/Base.vi')
        $scenarioRequireMobilePreview = $true
    }
    'signal-masscompile' {
        $scenarioBranchSuffix = 'signal-masscompile'
        $scenarioDescription  = 'same-commit mixed signal + masscompile change'
        $scenarioExpectation  = '`/vi-history` workflow itemizes both targets and reports at least one strict signal diff'
        $scenarioPlanHint     = '- Apply one real VI change + one LabVIEW masscompile rewrite in the same commit'
        $scenarioNeedsArtifactValidation = $true
        $scenarioTargetPaths = @('fixtures/vi-attr/Head.vi', 'fixtures/vi-attr/Base.vi')
        $scenarioTargetMinDiffs = @{
            'fixtures/vi-attr/Head.vi' = 1
            'fixtures/vi-attr/Base.vi' = 0
        }
        $scenarioDiffStatusRequiredTargets = @('fixtures/vi-attr/Head.vi')
        $scenarioRequireMobilePreview = $true
    }
    default {
        throw "Unsupported scenario: $Scenario"
    }
}

$timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
$branchName = "smoke/vi-history-$scenarioBranchSuffix-$timestamp"
$prTitle = "Smoke: VI history compare ($scenarioDescription; $timestamp)"
$prNote = "vi-history smoke $scenarioKey $timestamp"
$summaryDir = Join-Path 'tests' 'results' '_agent' 'smoke' 'vi-history'
New-Item -ItemType Directory -Path $summaryDir -Force | Out-Null
$summaryPath = Join-Path $summaryDir ("vi-history-smoke-{0}.json" -f $timestamp)
$workflowPath = '.github/workflows/pr-vi-history.yml'

$planSteps = [System.Collections.Generic.List[string]]::new()
$planSteps.Add("- Fetch origin/$BaseBranch") | Out-Null
$planSteps.Add("- Create branch $branchName from origin/$BaseBranch") | Out-Null
$planSteps.Add($scenarioPlanHint) | Out-Null
$planSteps.Add("- Push scratch branch and create draft PR") | Out-Null
$planSteps.Add("- Dispatch pr-vi-history.yml with PR input (max_pairs=$MaxPairs, base_ref=<effective>, head_ref=<effective>, include_merge_parents=$IncludeMergeParents)") | Out-Null
$planSteps.Add("- Wait for workflow completion and verify PR comment") | Out-Null
if ($scenarioNeedsArtifactValidation) {
    $planSteps.Add("- Download workflow artifact and validate diff/comparison counts") | Out-Null
}
$planSteps.Add("- Record summary under tests/results/_agent/smoke/vi-history/") | Out-Null
if (-not $KeepBranch) {
    $planSteps.Add("- Close draft PR and delete branch") | Out-Null
} else {
    $planSteps.Add("- Leave branch/PR for inspection (KeepBranch present)") | Out-Null
}

if ($DryRun) {
    Write-Host 'Dry-run mode: no changes will be made.'
    Write-Host 'Plan:'
    foreach ($step in $planSteps) {
        Write-Host "  $step"
    }
    return
}

$scratchContext = [ordered]@{
    Branch        = $branchName
    PrNumber      = $null
    PrUrl         = $null
    RunId         = $null
    CommentFound  = $false
    WorkflowUrl   = $null
    Success       = $false
    Note          = $prNote
    Scenario      = $scenarioKey
    CommitCount   = 0
    Comparisons   = $null
    Diffs         = $null
    ArtifactValidated = $false
    mobilePreviewValidated = $false
    mobilePreviewImageCount = 0
    mobilePreviewCommentFound = $false
    NetDiffAnchored = $false
    CompareBaseRef = $null
    CompareHeadRef = $null
    IncludeMergeParents = [bool]$IncludeMergeParents
}

$commitSummaries = @()

try {
    Invoke-Git -Arguments @('fetch', 'origin', $BaseBranch) | Out-Null

    Invoke-Git -Arguments @('checkout', "-B$branchName", "origin/$BaseBranch") | Out-Null

    $targetPaths = @($scenarioTargetPaths)
    if (-not $targetPaths -or $targetPaths.Count -eq 0) {
        $targetPaths = @('fixtures/vi-attr/Head.vi')
    }
    foreach ($targetPath in $targetPaths) {
        Enable-HistoryTracking -Path $targetPath
    }

    switch ($scenarioKey) {
        'attribute' {
            $commitSummaries = Invoke-AttributeHistoryCommit -TargetVi $targetPaths[0]
        }
        'sequential' {
            $commitSummaries = Invoke-SequentialHistoryCommits -TargetVi $targetPaths
            $netDiffArgs = @('diff', '--name-only', "origin/$BaseBranch", '--') + $targetPaths
            $netDiffPaths = @(Invoke-Git -Arguments $netDiffArgs)
            if ($netDiffPaths.Count -eq 0) {
                $anchorSourceVi = 'fixtures/vi-attr/Base.vi'
                $anchorTargetVi = $targetPaths[0]
                Write-Host ("Sequential scenario has no net diff against origin/{0}; applying anchor commit: {1} <= {2}" -f $BaseBranch, $anchorTargetVi, $anchorSourceVi)
                Copy-VIContent -Source $anchorSourceVi -Destination $anchorTargetVi
                $anchorStatus = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $anchorTargetVi))
                if ($anchorStatus.Count -eq 0) {
                    throw 'Failed to produce net diff anchor change for sequential scenario.'
                }
                Invoke-Git -Arguments @('add', '-f', $anchorTargetVi) | Out-Null
                $anchorMessage = 'chore: sequential history net-diff anchor'
                Invoke-Git -Arguments @('commit', '-m', $anchorMessage) | Out-Null
                $commitSummaries += [pscustomobject]@{
                    Title   = 'Net-diff anchor'
                    Source  = $anchorSourceVi
                    Targets = @($anchorTargetVi)
                    Message = $anchorMessage
                }
                $scratchContext.NetDiffAnchored = $true
            }
        }
        'sequential-multi-vi' {
            $commitSummaries = Invoke-SequentialHistoryCommits -TargetVi $targetPaths
            $netDiffArgs = @('diff', '--name-only', "origin/$BaseBranch", '--') + $targetPaths
            $netDiffPaths = @(Invoke-Git -Arguments $netDiffArgs)
            if ($netDiffPaths.Count -eq 0) {
                $anchorSourceVi = 'fixtures/vi-attr/Base.vi'
                $anchorTargetVi = $targetPaths[0]
                Write-Host ("Sequential scenario has no net diff against origin/{0}; applying anchor commit: {1} <= {2}" -f $BaseBranch, $anchorTargetVi, $anchorSourceVi)
                Copy-VIContent -Source $anchorSourceVi -Destination $anchorTargetVi
                $anchorStatus = @(Invoke-Git -Arguments @('status', '--porcelain', '--', $anchorTargetVi))
                if ($anchorStatus.Count -eq 0) {
                    throw 'Failed to produce net diff anchor change for sequential scenario.'
                }
                Invoke-Git -Arguments @('add', '-f', $anchorTargetVi) | Out-Null
                $anchorMessage = 'chore: sequential history net-diff anchor'
                Invoke-Git -Arguments @('commit', '-m', $anchorMessage) | Out-Null
                $commitSummaries += [pscustomobject]@{
                    Title   = 'Net-diff anchor'
                    Source  = $anchorSourceVi
                    Targets = @($anchorTargetVi)
                    Message = $anchorMessage
                }
                $scratchContext.NetDiffAnchored = $true
            }
        }
        'signal-masscompile' {
            $commitSummaries = Invoke-SignalMassCompileHistoryCommit -SignalTargetVi $targetPaths[0] -MassCompileTargetVi $targetPaths[1]
        }
    }
    $scratchContext.CommitCount = $commitSummaries.Count
    $effectiveCompareBaseRef = if ([string]::IsNullOrWhiteSpace($CompareBaseRef)) { $BaseBranch } else { $CompareBaseRef.Trim() }
    $effectiveCompareHeadRef = if ([string]::IsNullOrWhiteSpace($CompareHeadRef)) { $branchName } else { $CompareHeadRef.Trim() }
    if ([string]::IsNullOrWhiteSpace($effectiveCompareBaseRef) -or [string]::IsNullOrWhiteSpace($effectiveCompareHeadRef)) {
        throw 'Effective compare refs cannot be empty.'
    }
    if ([string]::Equals($effectiveCompareBaseRef, $effectiveCompareHeadRef, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Effective compare refs must differ.'
    }
    $scratchContext.CompareBaseRef = $effectiveCompareBaseRef
    $scratchContext.CompareHeadRef = $effectiveCompareHeadRef

    Invoke-Git -Arguments @('push', '-u', 'origin', $branchName) | Out-Null

    Write-Host "Creating draft PR for branch $branchName..."
    $prBodyLines = New-Object System.Collections.Generic.List[string]
    $prBodyLines.Add('# VI history smoke test') | Out-Null
    $prBodyLines.Add('') | Out-Null
    $prBodyLines.Add('*This PR was generated by tools/Test-PRVIHistorySmoke.ps1.*') | Out-Null
    $prBodyLines.Add('') | Out-Null
    $prBodyLines.Add("- Scenario: $scenarioDescription") | Out-Null
    $prBodyLines.Add("- Expectation: $scenarioExpectation") | Out-Null
    if ($commitSummaries.Count -gt 0) {
        $prBodyLines.Add('') | Out-Null
        $prBodyLines.Add('- Steps:') | Out-Null
        foreach ($commitSummary in $commitSummaries) {
            $targetDisplay = $null
            if ($commitSummary.PSObject.Properties['Targets'] -and $commitSummary.Targets) {
                $targetDisplay = [string]::Join(', ', @($commitSummary.Targets))
            }
            if ([string]::IsNullOrWhiteSpace($targetDisplay)) {
                $prBodyLines.Add(("  - {0} (`{1}`)" -f $commitSummary.Title, $commitSummary.Source)) | Out-Null
            } else {
                $prBodyLines.Add(("  - {0} (`{1}` -> `{2}`)" -f $commitSummary.Title, $commitSummary.Source, $targetDisplay)) | Out-Null
            }
        }
    }
    $prBody = $prBodyLines -join "`n"
    Invoke-Gh -Arguments @('pr', 'create',
        '--repo', $repoInfo.Slug,
        '--base', $BaseBranch,
        '--head', $branchName,
        '--title', $prTitle,
        '--body', $prBody,
        '--draft') | Out-Null

    $prInfo = Get-PullRequestInfo -Repo $repoInfo -Branch $branchName
    $scratchContext.PrNumber = [int]$prInfo.number
    $scratchContext.PrUrl = $prInfo.html_url
    Write-Host "Draft PR ##$($scratchContext.PrNumber) created at $($scratchContext.PrUrl)."

    $auth = Get-GitHubAuth
    $dispatchUri = "https://api.github.com/repos/$($repoInfo.Slug)/actions/workflows/pr-vi-history.yml/dispatches"
    $dispatchBody = @{
        ref    = $branchName
        inputs = @{
            pr                    = $scratchContext.PrNumber.ToString()
            max_pairs             = $MaxPairs.ToString()
            base_ref              = $effectiveCompareBaseRef
            head_ref              = $effectiveCompareHeadRef
            include_merge_parents = if ($IncludeMergeParents.IsPresent) { 'true' } else { 'false' }
        }
    } | ConvertTo-Json -Depth 4
    Write-Host 'Triggering pr-vi-history workflow via dispatch API...'
    Invoke-RestMethod -Uri $dispatchUri -Headers $auth.Headers -Method Post -Body $dispatchBody -ContentType 'application/json'
    Write-Host 'Workflow dispatch accepted.'

    Write-Host 'Waiting for workflow run to appear...'
    $runId = $null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $runs = Invoke-Gh -Arguments @(
            'run', 'list',
            '--workflow', 'pr-vi-history.yml',
            '--branch', $branchName,
            '--limit', '1',
            '--json', 'databaseId,status,conclusion,headBranch'
        ) -ExpectJson
        if ($runs -and $runs.Count -gt 0 -and $runs[0].headBranch -eq $branchName) {
            $runId = $runs[0].databaseId
            if ($runs[0].status -eq 'completed') { break }
        }
        Start-Sleep -Seconds 5
    }
    if (-not $runId) {
        throw 'Unable to locate dispatched workflow run.'
    }
    $scratchContext.RunId = $runId
    $scratchContext.WorkflowUrl = "https://github.com/$($repoInfo.Slug)/actions/runs/$runId"
    Write-Host "Workflow run id: $runId"

    Write-Host "Watching workflow run $runId..."
    Invoke-Gh -Arguments @('run', 'watch', $runId.ToString(), '--exit-status') | Out-Null

    $runSummary = Invoke-Gh -Arguments @('run', 'view', $runId.ToString(), '--json', 'conclusion') -ExpectJson
    if ($runSummary.conclusion -ne 'success') {
        throw "Workflow run $runId concluded with '$($runSummary.conclusion)'."
    }

    Write-Host 'Verifying PR comment includes history summary...'
    $prDetails = Invoke-Gh -Arguments @('pr', 'view', $scratchContext.PrNumber.ToString(), '--repo', $repoInfo.Slug, '--json', 'comments') -ExpectJson
    $commentBodies = @()
    if ($prDetails -and $prDetails.comments) {
        $commentBodies = @($prDetails.comments | ForEach-Object { $_.body })
    }
    $historyComment = $commentBodies | Where-Object { $_ -like '*VI history compare*' } | Select-Object -First 1
    $scratchContext.CommentFound = [bool]$historyComment
    if (-not $historyComment) {
        throw 'Expected `/vi-history` comment not found on the draft PR.'
    }
    $mobilePreviewHeaderMatch = [regex]::Match($historyComment, '(?im)^###\s+Mobile Preview\s*$')
    $mobilePreviewImageMatches = [regex]::Matches($historyComment, '<img\s+[^>]*src=["''][^"''>]*history-image-[^"''>]*["''][^>]*>')
    $scratchContext.mobilePreviewCommentFound = $mobilePreviewHeaderMatch.Success
    $scratchContext.mobilePreviewImageCount = $mobilePreviewImageMatches.Count

    $expectedRowTargets = @()
    if ($scenarioNeedsArtifactValidation) {
        $expectedRowTargets = @($scenarioTargetPaths)
    } else {
        $expectedRowTargets = @('fixtures/vi-attr/Head.vi')
    }

    $rowMatches = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($expectedTarget in $expectedRowTargets) {
        $escapedTarget = [regex]::Escape($expectedTarget)
        $rowPattern = ('\|\s*<code>{0}</code>\s*\|\s*(?<change>[^|]+)\|\s*(?<comparisons>\d+)\s*\|\s*(?<diffs>\d+)\s*\|\s*(?<status>[^|]+)\|' -f $escapedTarget)
        $rowMatch = [regex]::Match($historyComment, $rowPattern)
        if ($rowMatch.Success) {
            $rowMatches.Add([pscustomobject]@{
                targetPath  = $expectedTarget
                comparisons = [int]$rowMatch.Groups['comparisons'].Value
                diffs       = [int]$rowMatch.Groups['diffs'].Value
                status      = $rowMatch.Groups['status'].Value.Trim()
            }) | Out-Null
        }
    }

    if ($rowMatches.Count -gt 0) {
        $scratchContext.Comparisons = ($rowMatches | Measure-Object -Property comparisons -Sum).Sum
        $scratchContext.Diffs = ($rowMatches | Measure-Object -Property diffs -Sum).Sum
    } else {
        Write-Warning 'Unable to parse comparison/diff counts from the history comment.'
    }

    if ($scenarioNeedsArtifactValidation) {
        if ($rowMatches.Count -lt $expectedRowTargets.Count) {
            $missingTargets = @($expectedRowTargets | Where-Object {
                $target = $_
                -not ($rowMatches | Where-Object { $_.targetPath -eq $target })
            })
            throw ("Failed to parse sequential summary rows for target(s): {0}" -f ($missingTargets -join ', '))
        }

        foreach ($row in $rowMatches) {
            if ($row.comparisons -lt [Math]::Max(1, $commitSummaries.Count)) {
                throw ("Expected at least {0} comparisons for {1}, but comment reported {2}." -f [Math]::Max(1, $commitSummaries.Count), $row.targetPath, $row.comparisons)
            }
            $minDiffs = if ($scenarioTargetMinDiffs.ContainsKey($row.targetPath)) { [int]$scenarioTargetMinDiffs[$row.targetPath] } else { 1 }
            if ($row.diffs -lt $minDiffs) {
                throw ("History comment should report at least {0} diff(s) for {1}." -f $minDiffs, $row.targetPath)
            }
            if ($scenarioDiffStatusRequiredTargets -contains $row.targetPath -and $row.status -notlike '*diff*') {
                throw ("Expected status column to mark diff for {0} but saw '{1}'." -f $row.targetPath, $row.status)
            }
        }

        if ($scenarioRequireMobilePreview -and -not $mobilePreviewHeaderMatch.Success) {
            throw 'Sequential history comment is missing the `### Mobile Preview` section.'
        }
        if ($scenarioRequireMobilePreview -and $mobilePreviewImageMatches.Count -lt 1) {
            throw 'Sequential history comment did not include preview image tags (`history-image-*`).'
        }

        $artifactDir = Join-Path $summaryDir ("artifact-$timestamp")
        New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
        Invoke-Gh -Arguments @(
            'run', 'download',
            $runId.ToString(),
            '--name', ("pr-vi-history-{0}" -f $scratchContext.PrNumber),
            '--dir', $artifactDir
        ) | Out-Null

        $summaryFile = Get-ChildItem -LiteralPath $artifactDir -Recurse -Filter 'vi-history-summary.json' | Select-Object -First 1
        if (-not $summaryFile) {
            throw 'Summary JSON not found in downloaded artifact.'
        }
        $summaryData = Get-Content -LiteralPath $summaryFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $summaryData.targets -or @($summaryData.targets).Count -eq 0) {
            throw 'Summary JSON does not contain target entries.'
        }

        foreach ($expectedTarget in $expectedRowTargets) {
            $targetSummary = @($summaryData.targets | Where-Object { $_.repoPath -eq $expectedTarget } | Select-Object -First 1)
            if (-not $targetSummary -or $targetSummary.Count -eq 0) {
                throw ("Summary JSON missing expected target entry: {0}" -f $expectedTarget)
            }
            $artifactComparisons = if ($targetSummary[0].stats) { [int]$targetSummary[0].stats.processed } else { 0 }
            $artifactDiffs = if ($targetSummary[0].stats) { [int]$targetSummary[0].stats.diffs } else { 0 }
            if ($artifactComparisons -lt [Math]::Max(1, $commitSummaries.Count)) {
                throw ("Summary JSON reported {0} comparisons for {1}; expected at least {2}." -f $artifactComparisons, $expectedTarget, [Math]::Max(1, $commitSummaries.Count))
            }
            $artifactMinDiffs = if ($scenarioTargetMinDiffs.ContainsKey($expectedTarget)) { [int]$scenarioTargetMinDiffs[$expectedTarget] } else { 1 }
            if ($artifactDiffs -lt $artifactMinDiffs) {
                throw ("Summary JSON should report at least {0} diff(s) for {1} in history smoke." -f $artifactMinDiffs, $expectedTarget)
            }
        }

        $imageIndexFiles = Get-ChildItem -LiteralPath $artifactDir -Recurse -Filter 'vi-history-image-index.json' -File
        if (-not $imageIndexFiles -or $imageIndexFiles.Count -lt 1) {
            throw 'vi-history-image-index.json not found in downloaded artifact.'
        }
        $previewImageFiles = Get-ChildItem -LiteralPath $artifactDir -Recurse -File |
            Where-Object { $_.Name -like 'history-image-*' -and $_.FullName -match '[\\/]+previews[\\/]' }
        if (-not $previewImageFiles -or $previewImageFiles.Count -lt 1) {
            throw 'Preview image files (`previews/history-image-*`) not found in downloaded artifact.'
        }
        $scratchContext.mobilePreviewImageCount = [Math]::Max($scratchContext.mobilePreviewImageCount, $previewImageFiles.Count)
        $scratchContext.mobilePreviewValidated = $true
        $scratchContext.ArtifactValidated = $true
        try {
            Remove-Item -LiteralPath $artifactDir -Recurse -Force
        } catch {
            Write-Warning ("Failed to delete temporary artifact directory {0}: {1}" -f $artifactDir, $_.Exception.Message)
        }
    }

    $scratchContext.Success = $true
    Write-Host 'Smoke run succeeded.'
}
catch {
    $scratchContext.Success = $false
    $scratchContext.ErrorMessage = $_.Exception.Message
    Write-Error $_
    throw
}
finally {
    try {
        Invoke-Git -Arguments @('checkout', $initialBranch) | Out-Null
    } catch {
        Write-Warning ("Failed to return to initial branch {0}: {1}" -f $initialBranch, $_.Exception.Message)
    }
    if ($scenarioTargetPaths -and $scenarioTargetPaths.Count -gt 0) {
        foreach ($trackedTarget in $scenarioTargetPaths) {
            Restore-HistoryTracking -Path $trackedTarget
        }
    } else {
        Restore-HistoryTracking -Path 'fixtures/vi-attr/Head.vi'
    }

    if (-not $KeepBranch) {
        Write-Host 'Cleaning up scratch PR and branch...'
        try {
            if ($scratchContext.PrNumber) {
                Invoke-Gh -Arguments @('pr', 'close', $scratchContext.PrNumber.ToString(), '--repo', $repoInfo.Slug, '--delete-branch') | Out-Null
            }
        } catch {
            Write-Warning "PR cleanup encountered an issue: $($_.Exception.Message)"
        }
        try {
            Invoke-Git -Arguments @('branch', '-D', $branchName) | Out-Null
        } catch {
            # ignore branch delete failures
        }
        try {
            Invoke-Git -Arguments @('push', 'origin', "--delete", $branchName) | Out-Null
        } catch {
            # ignore remote delete failures
        }
    } else {
        Write-Host 'KeepBranch specified - leaving scratch PR and branch in place.'
    }

    $scratchContext.SummaryGeneratedAt = (Get-Date).ToString('o')
    $scratchContext.KeepBranch = [bool]$KeepBranch
    $scratchContext.BaseBranch = $BaseBranch
    $scratchContext.MaxPairs = $MaxPairs
    $scratchContext.InitialBranch = $initialBranch

    $scratchContext | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8
    Write-Host "Summary written to $summaryPath"
}
