#Requires -Version 7.0

param(
  [string]$RepoPath,
  [string]$BaseRef,
  [string]$HeadRef = 'HEAD',
  [int]$MaxCommits = 50,
  [string]$WorkspaceRoot,
  [string]$StageNamePrefix = 'commit',
  [switch]$SkipSync,
  [switch]$SkipValidate,
  [switch]$SkipLVCompare,
  [switch]$DryRun,
  [string]$LabVIEWExePath,
  [string]$SummaryPath,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

function Resolve-RepoRoot {
  param([string]$StartPath = (Get-Location).Path)
  try {
    return (git -C $StartPath rev-parse --show-toplevel 2>$null).Trim()
  } catch {
    return $StartPath
  }
}

function Normalize-RepoPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $normalized = $Path.Replace('\', '/')
  while ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }
  if ($normalized.StartsWith('/')) { $normalized = $normalized.Substring(1) }
  return $normalized
}

function Get-ShortCommit {
  param([string]$Hash)
  if ([string]::IsNullOrWhiteSpace($Hash)) { return '(unknown)' }
  if ($Hash.Length -le 8) { return $Hash }
  return $Hash.Substring(0,8)
}

function Get-ParentCommit {
  param(
    [string]$RepoPath,
    [string]$Commit
  )
  if ([string]::IsNullOrWhiteSpace($Commit)) { return $null }
  $args = @('-C', $RepoPath, 'rev-parse', '--verify', "$Commit`^")
  $output = & git @args 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return ($output -split "`n")[0].Trim()
}

function Get-BlobHash {
  param(
    [string]$RepoPath,
    [string]$Commit,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($Commit) -or [string]::IsNullOrWhiteSpace($Path)) { return $null }
  $args = @('-C', $RepoPath, 'rev-parse', "$Commit`:$Path")
  $output = & git @args 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return ($output -split "`n")[0].Trim()
}

function Resolve-CompareDecision {
  param(
    [string]$Status,
    [string]$Path,
    [string]$OldPath,
    [string]$BaseHash,
    [string]$HeadHash
  )

  $normalizedPath = Normalize-RepoPath -Path ($Path ?? $OldPath)
  if (-not $Status) {
    return [pscustomobject]@{ Compare = $true; Reason = 'unknown status'; Path = $normalizedPath }
  }

  $statusCode = $Status.Substring(0,1).ToUpperInvariant()

  switch ($statusCode) {
    'D' {
      return [pscustomobject]@{ Compare = $false; Reason = 'deleted file'; Path = $normalizedPath }
    }
    'R' {
      $score = $Status.Substring(1)
      $pureRename = $false
      if ($score -and ($score -match '^\d+$')) {
        $pureRename = ([int]$score -eq 100)
      }
      if ($pureRename -and $BaseHash -and $HeadHash -and ($BaseHash -eq $HeadHash)) {
        return [pscustomobject]@{ Compare = $false; Reason = 'rename without content change'; Path = $normalizedPath }
      }
      if ($BaseHash -and $HeadHash -and ($BaseHash -eq $HeadHash)) {
        return [pscustomobject]@{ Compare = $false; Reason = 'content unchanged after rename'; Path = $normalizedPath }
      }
      return [pscustomobject]@{ Compare = $true; Reason = 'rename with modifications'; Path = $normalizedPath }
    }
    'C' {
      if ($BaseHash -and $HeadHash -and ($BaseHash -eq $HeadHash)) {
        return [pscustomobject]@{ Compare = $false; Reason = 'copy identical to source'; Path = $normalizedPath }
      }
      return [pscustomobject]@{ Compare = $true; Reason = 'copy with modifications'; Path = $normalizedPath }
    }
    default {
      if ($BaseHash -and $HeadHash -and ($BaseHash -eq $HeadHash)) {
        return [pscustomobject]@{ Compare = $false; Reason = 'content unchanged'; Path = $normalizedPath }
      }
      return [pscustomobject]@{ Compare = $true; Reason = 'modified'; Path = $normalizedPath }
    }
  }
}

$codeRepoRoot = Resolve-RepoRoot -StartPath $PSScriptRoot
$sweepScript = Join-Path $codeRepoRoot 'tools/icon-editor/Invoke-VIDiffSweep.ps1'
if (-not (Test-Path -LiteralPath $sweepScript -PathType Leaf)) {
  throw "Invoke-VIDiffSweep.ps1 not found at '$sweepScript'."
}

$sweepWrapper = $null
Push-Location $codeRepoRoot
try {
  $sweepWrapper = & $sweepScript `
    -RepoPath $RepoPath `
    -BaseRef $BaseRef `
    -HeadRef $HeadRef `
    -MaxCommits $MaxCommits `
    -SkipSync:$SkipSync `
    -Quiet:$Quiet
}
finally {
  Pop-Location
}

if (-not $sweepWrapper) {
  throw 'Invoke-VIDiffSweep.ps1 returned no data.'
}

$candidates = $sweepWrapper.candidates
if (-not $candidates) {
  throw 'Invoke-VIDiffSweep.ps1 did not return candidate metadata.'
}

$repoResolved = $candidates.repoPath
$commitResults = New-Object System.Collections.Generic.List[object]

if (-not $repoResolved) {
  throw 'Failed to resolve repository for sweep.'
}

$commitList = if ($candidates.PSObject.Properties['commits'] -and $candidates.commits) { $candidates.commits } else { @() }

foreach ($commit in $commitList) {
  $parentCommit = Get-ParentCommit -RepoPath $repoResolved -Commit $commit.commit
  $comparePaths = New-Object System.Collections.Generic.List[string]
  $skipped = New-Object System.Collections.Generic.List[object]

  foreach ($file in $commit.files) {
    $normalizedPath = Normalize-RepoPath -Path $file.path
    $oldPath = if ($file.oldPath) { Normalize-RepoPath -Path $file.oldPath } else { $normalizedPath }
    $basePath = if ($file.oldPath) { $file.oldPath } else { $file.path }

    $baseHash = if ($parentCommit) { Get-BlobHash -RepoPath $repoResolved -Commit $parentCommit -Path $basePath } else { $null }
    $headHash = Get-BlobHash -RepoPath $repoResolved -Commit $commit.commit -Path $file.path

    $decision = Resolve-CompareDecision -Status $file.status -Path $file.path -OldPath $file.oldPath -BaseHash $baseHash -HeadHash $headHash
    if ($decision.Compare) {
      $comparePaths.Add($normalizedPath) | Out-Null
    } else {
      $skipped.Add([pscustomobject]@{
          path   = $normalizedPath
          reason = $decision.Reason
        }) | Out-Null
    }
  }

  if (-not $Quiet) {
    if ($comparePaths.Count -eq 0) {
      $skipReasons = ($skipped | Select-Object -ExpandProperty reason -Unique)
      $reasonText = if ($skipReasons -and $skipReasons.Count -gt 0) { $skipReasons -join ', ' } else { 'no compare candidates' }
      Write-Information ("Commit {0}: all VI changes skipped ({1})" -f (Get-ShortCommit -Hash $commit.commit), $reasonText)
    } else {
      Write-Information ("Commit {0}: comparing {1} file(s)" -f (Get-ShortCommit -Hash $commit.commit), $comparePaths.Count)
    }
  }

  $commitResult = [ordered]@{
    commit       = $commit.commit
    author       = $commit.author
    authorDate   = $commit.authorDate
    subject      = $commit.subject
    comparePaths = $comparePaths.ToArray()
    skipped      = $skipped.ToArray()
  }
  $commitResults.Add([pscustomobject]$commitResult) | Out-Null

  if ($comparePaths.Count -gt 0 -and -not $DryRun.IsPresent) {
    $shortCommit = Get-ShortCommit -Hash $commit.commit
    $stageName = "{0}-{1}" -f $StageNamePrefix, $shortCommit
    $commitScript = Join-Path $codeRepoRoot 'tools/icon-editor/Invoke-VIComparisonFromCommit.ps1'
    if (-not (Test-Path -LiteralPath $commitScript -PathType Leaf)) {
      throw "Invoke-VIComparisonFromCommit.ps1 not found at '$commitScript'."
    }
    $compareParams = @{
      Commit        = $commit.commit
      RepoPath      = $repoResolved
      WorkspaceRoot = $WorkspaceRoot
      StageName     = $stageName
      IncludePaths  = $comparePaths.ToArray()
      LabVIEWExePath= $LabVIEWExePath
      SkipSync      = $true
    }
    if ($SkipValidate.IsPresent) { $compareParams['SkipValidate'] = $true }
    if ($SkipLVCompare.IsPresent) { $compareParams['SkipLVCompare'] = $true }
    & $commitScript @compareParams | Out-Null
  }
}

$result = [pscustomobject]@{
  repoPath     = $repoResolved
  baseRef      = $candidates.baseRef
  headRef      = $candidates.headRef
  totalCommits = $commitResults.Count
  commits      = $commitResults.ToArray()
  candidates   = $candidates
  outputPath   = $sweepWrapper.outputPath
}

if ($SummaryPath) {
  $summaryDir = Split-Path -Parent $SummaryPath
  if ($summaryDir -and -not (Test-Path -LiteralPath $summaryDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $summaryDir -Force)
  }
  $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $SummaryPath -Encoding utf8
}

return $result
