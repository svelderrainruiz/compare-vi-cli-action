Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VIHistorySlicePropertyValue {
  param(
    [AllowNull()]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Resolve-VIHistorySliceAbsolutePath {
  param(
    [Parameter(Mandatory = $true)][string]$BasePath,
    [Parameter(Mandatory = $true)][string]$PathValue
  )

  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Test-VIHistorySlicePathWithinRoot {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [Parameter(Mandatory = $true)][string]$CandidatePath
  )

  $comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }

  $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
  $normalizedCandidate = [System.IO.Path]::GetFullPath($CandidatePath)
  if ([string]::Equals($normalizedRoot, $normalizedCandidate, $comparison)) {
    return $true
  }

  $normalizedRootWithSeparator = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
  return $normalizedCandidate.StartsWith($normalizedRootWithSeparator, $comparison)
}

function ConvertTo-VIHistorySliceRepoRelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$PathValue,
    [Parameter(Mandatory = $true)][string]$PropertyName
  )

  $trimmed = $PathValue.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    throw ("Selector property '{0}' must not be empty." -f $PropertyName)
  }

  if ([System.IO.Path]::IsPathRooted($trimmed)) {
    $absolutePath = [System.IO.Path]::GetFullPath($trimmed)
    if (-not (Test-VIHistorySlicePathWithinRoot -RootPath $RepoRoot -CandidatePath $absolutePath)) {
      throw ("Selector property '{0}' must stay within repo root '{1}': {2}" -f $PropertyName, $RepoRoot, $absolutePath)
    }
    $relativePath = [System.IO.Path]::GetRelativePath($RepoRoot, $absolutePath)
  } else {
    $relativePath = $trimmed
  }

  $normalized = $relativePath.Replace('\', '/')
  while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
    $normalized = $normalized.Substring(2)
  }

  return $normalized
}

function Invoke-VIHistorySliceGit {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowFailure
  )

  $output = & git -C $RepoRoot @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw ("git -C {0} {1} failed with exit code {2}`n{3}" -f $RepoRoot, ($Arguments -join ' '), $exitCode, ($output -join [Environment]::NewLine))
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($output | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
  }
}

function Resolve-VIHistorySliceRepoRoot {
  param([Parameter(Mandatory = $true)][string]$PathValue)

  $candidate = Resolve-VIHistorySliceAbsolutePath -BasePath (Get-Location).Path -PathValue $PathValue
  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
    throw ("Selector repoPath does not exist: {0}" -f $candidate)
  }

  $probe = Invoke-VIHistorySliceGit -RepoRoot $candidate -Arguments @('rev-parse', '--show-toplevel')
  if ($probe.Output.Count -eq 0) {
    throw ("Unable to resolve git repo root from selector repoPath: {0}" -f $candidate)
  }

  return [System.IO.Path]::GetFullPath($probe.Output[0].Trim())
}

function Resolve-VIHistorySliceCommitSha {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Ref,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $spec = ('{0}^{{commit}}' -f $Ref)
  $result = Invoke-VIHistorySliceGit -RepoRoot $RepoRoot -Arguments @('rev-parse', $spec)
  if ($result.Output.Count -eq 0) {
    throw ("Unable to resolve {0} commit SHA from ref '{1}'." -f $Label, $Ref)
  }

  return $result.Output[0].Trim()
}

function Resolve-VIHistorySliceFirstParentSha {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$CommitSha
  )

  $result = Invoke-VIHistorySliceGit -RepoRoot $RepoRoot -Arguments @('rev-parse', ('{0}^' -f $CommitSha)) -AllowFailure
  if ($result.ExitCode -ne 0 -or $result.Output.Count -eq 0) {
    return $null
  }

  return $result.Output[0].Trim()
}

function Resolve-VIHistorySliceMergeBaseSha {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$LeftSha,
    [Parameter(Mandatory = $true)][string]$RightSha
  )

  $result = Invoke-VIHistorySliceGit -RepoRoot $RepoRoot -Arguments @('merge-base', $LeftSha, $RightSha)
  if ($result.Output.Count -eq 0) {
    throw ("Unable to resolve merge-base for '{0}' and '{1}'." -f $LeftSha, $RightSha)
  }

  return $result.Output[0].Trim()
}

function Resolve-VIHistorySliceRepoIdentity {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [AllowEmptyString()][string]$RequestedIdentity
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedIdentity)) {
    return [pscustomobject]@{
      value = [string]$RequestedIdentity.Trim()
      source = 'parameter'
    }
  }

  $originUrlResult = Invoke-VIHistorySliceGit -RepoRoot $RepoRoot -Arguments @('config', '--get', 'remote.origin.url') -AllowFailure
  if ($originUrlResult.ExitCode -eq 0 -and $originUrlResult.Output.Count -gt 0) {
    $originUrl = $originUrlResult.Output[0].Trim()
    if ($originUrl -match 'github\.com[:/](?<slug>[^/]+/[^/.]+?)(?:\.git)?$') {
      return [pscustomobject]@{
        value = [string]$Matches['slug']
        source = 'git-origin-url'
      }
    }
  }

  return [pscustomobject]@{
    value = ''
    source = 'unspecified'
  }
}

function Test-VIHistorySliceCommitTouchesPath {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$CommitSha,
    [Parameter(Mandatory = $true)][string]$PathFilter
  )

  $args = @('diff-tree', '--root', '--no-commit-id', '--name-only', '-r', $CommitSha, '--', $PathFilter)
  $result = Invoke-VIHistorySliceGit -RepoRoot $RepoRoot -Arguments $args
  return (@($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })).Count -gt 0
}

function Get-VIHistorySliceDigest {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RepoIdentity,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$PathFilter,
    [Parameter(Mandatory = $true)][string]$HeadSha,
    [AllowNull()][string]$BaselineSha,
    [AllowNull()][string]$MergeBaseSha,
    [Parameter(Mandatory = $true)][string]$BaselineMode,
    [Parameter(Mandatory = $true)][string]$HistoryMode,
    [Parameter(Mandatory = $true)][int]$SelectionPolicyVersion,
    [AllowNull()][int]$MaxPairs,
    [AllowEmptyCollection()][string[]]$CandidateCommits = @(),
    [AllowEmptyCollection()][string[]]$SelectedPairs = @()
  )

  $lines = @(
    'schema=vi-history/slice-manifest@v1',
    ('repoIdentity={0}' -f ($RepoIdentity ?? '')),
    ('targetPath={0}' -f $TargetPath),
    ('pathFilter={0}' -f $PathFilter),
    ('headSha={0}' -f $HeadSha),
    ('baselineSha={0}' -f ($(if ([string]::IsNullOrWhiteSpace($BaselineSha)) { '' } else { $BaselineSha }))),
    ('mergeBaseSha={0}' -f ($(if ([string]::IsNullOrWhiteSpace($MergeBaseSha)) { '' } else { $MergeBaseSha }))),
    ('baselineMode={0}' -f $BaselineMode),
    ('historyMode={0}' -f $HistoryMode),
    ('selectionPolicyVersion={0}' -f $SelectionPolicyVersion),
    ('maxPairs={0}' -f ($(if ($null -eq $MaxPairs) { '' } else { [string]$MaxPairs }))),
    ('candidateCommits={0}' -f ([string]::Join(',', @($CandidateCommits)))),
    ('selectedPairs={0}' -f ([string]::Join(',', @($SelectedPairs))))
  )

  $payload = [System.Text.Encoding]::UTF8.GetBytes(([string]::Join("`n", $lines)))
  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $hasher.ComputeHash($payload)
  } finally {
    $hasher.Dispose()
  }

  return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Resolve-VIHistorySliceManifest {
  [CmdletBinding(DefaultParameterSetName = 'SelectorPath')]
  param(
    [Parameter(ParameterSetName = 'SelectorPath', Mandatory = $true)]
    [string]$SelectorPath,

    [Parameter(ParameterSetName = 'SelectorObject', Mandatory = $true)]
    [psobject]$Selector
  )

  $selectorObject = $Selector
  $selectorBasePath = (Get-Location).Path
  if ($PSCmdlet.ParameterSetName -eq 'SelectorPath') {
    $selectorPathResolved = Resolve-VIHistorySliceAbsolutePath -BasePath $selectorBasePath -PathValue $SelectorPath
    if (-not (Test-Path -LiteralPath $selectorPathResolved -PathType Leaf)) {
      throw ("SelectorPath does not exist: {0}" -f $selectorPathResolved)
    }
    $selectorBasePath = Split-Path -Parent $selectorPathResolved
    try {
      $selectorObject = Get-Content -LiteralPath $selectorPathResolved -Raw | ConvertFrom-Json -Depth 16 -ErrorAction Stop
    } catch {
      throw ("Unable to parse selector JSON '{0}': {1}" -f $selectorPathResolved, $_.Exception.Message)
    }
  }

  $schema = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'schema')
  if (-not [string]::Equals($schema, 'vi-history/slice-selector@v1', [System.StringComparison]::Ordinal)) {
    throw ("Unsupported selector schema '{0}'. Expected 'vi-history/slice-selector@v1'." -f $schema)
  }

  $repoPathInput = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'repoPath')
  if ([string]::IsNullOrWhiteSpace($repoPathInput)) {
    $repoPathInput = '.'
  }
  $repoPathResolved = Resolve-VIHistorySliceAbsolutePath -BasePath $selectorBasePath -PathValue $repoPathInput
  $repoRoot = Resolve-VIHistorySliceRepoRoot -PathValue $repoPathResolved

  $targetPathInput = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'targetPath')
  if ([string]::IsNullOrWhiteSpace($targetPathInput)) {
    throw 'Selector targetPath is required.'
  }
  $pathFilterInput = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'pathFilter')
  if ([string]::IsNullOrWhiteSpace($pathFilterInput)) {
    $pathFilterInput = $targetPathInput
  }

  $targetPath = ConvertTo-VIHistorySliceRepoRelativePath -RepoRoot $repoRoot -PathValue $targetPathInput -PropertyName 'targetPath'
  $pathFilter = ConvertTo-VIHistorySliceRepoRelativePath -RepoRoot $repoRoot -PathValue $pathFilterInput -PropertyName 'pathFilter'

  $headRef = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'headRef')
  if ([string]::IsNullOrWhiteSpace($headRef)) {
    $headRef = 'HEAD'
  }
  $baselineRef = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'baselineRef')

  $baselineMode = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'baselineMode')
  if ([string]::IsNullOrWhiteSpace($baselineMode)) {
    $baselineMode = if ([string]::IsNullOrWhiteSpace($baselineRef)) { 'head-parent' } else { 'merge-base' }
  }
  if ($baselineMode -notin @('explicit', 'merge-base', 'head-parent')) {
    throw ("Unsupported selector baselineMode '{0}'." -f $baselineMode)
  }

  $historyMode = [string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'historyMode')
  if ([string]::IsNullOrWhiteSpace($historyMode)) {
    $historyMode = 'first-parent'
  }
  if ($historyMode -notin @('first-parent', 'ancestry-path', 'explicit-list')) {
    throw ("Unsupported selector historyMode '{0}'." -f $historyMode)
  }

  $selectionPolicyVersion = Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'selectionPolicyVersion'
  if ($null -eq $selectionPolicyVersion) {
    $selectionPolicyVersion = 1
  }
  $selectionPolicyVersion = [int]$selectionPolicyVersion
  if ($selectionPolicyVersion -lt 1) {
    throw 'Selector selectionPolicyVersion must be greater than zero.'
  }

  $maxCommitCount = Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'maxCommitCount'
  if ($null -ne $maxCommitCount) {
    $maxCommitCount = [int]$maxCommitCount
    if ($maxCommitCount -le 0) {
      throw 'Selector maxCommitCount must be greater than zero when specified.'
    }
  }

  $maxPairs = Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'maxPairs'
  if ($null -ne $maxPairs) {
    $maxPairs = [int]$maxPairs
    if ($maxPairs -le 0) {
      throw 'Selector maxPairs must be greater than zero when specified.'
    }
  }

  $explicitCommitRefs = @()
  $explicitCommitProperty = Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'explicitCommits'
  if ($null -ne $explicitCommitProperty) {
    $explicitCommitRefs = @($explicitCommitProperty | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  }

  if ($historyMode -eq 'explicit-list' -and $explicitCommitRefs.Count -eq 0) {
    throw 'Selector explicitCommits is required when historyMode is explicit-list.'
  }

  $repoIdentity = Resolve-VIHistorySliceRepoIdentity -RepoRoot $repoRoot -RequestedIdentity ([string](Get-VIHistorySlicePropertyValue -Object $selectorObject -Name 'repoIdentity'))

  $headSha = Resolve-VIHistorySliceCommitSha -RepoRoot $repoRoot -Ref $headRef -Label 'headRef'
  $baselineRefSha = $null
  if (-not [string]::IsNullOrWhiteSpace($baselineRef)) {
    $baselineRefSha = Resolve-VIHistorySliceCommitSha -RepoRoot $repoRoot -Ref $baselineRef -Label 'baselineRef'
  }

  $baselineSha = $null
  switch ($baselineMode) {
    'explicit' {
      if ([string]::IsNullOrWhiteSpace($baselineRef)) {
        throw 'Selector baselineRef is required when baselineMode is explicit.'
      }
      $baselineSha = $baselineRefSha
    }
    'merge-base' {
      if ([string]::IsNullOrWhiteSpace($baselineRef)) {
        throw 'Selector baselineRef is required when baselineMode is merge-base.'
      }
      $baselineSha = Resolve-VIHistorySliceMergeBaseSha -RepoRoot $repoRoot -LeftSha $headSha -RightSha $baselineRefSha
    }
    'head-parent' {
      $baselineSha = Resolve-VIHistorySliceFirstParentSha -RepoRoot $repoRoot -CommitSha $headSha
    }
  }

  $mergeBaseSha = if (-not [string]::IsNullOrWhiteSpace($baselineRefSha)) {
    Resolve-VIHistorySliceMergeBaseSha -RepoRoot $repoRoot -LeftSha $headSha -RightSha $baselineRefSha
  } elseif (-not [string]::IsNullOrWhiteSpace($baselineSha)) {
    [string]$baselineSha
  } else {
    $null
  }

  $rangeExpression = if ($historyMode -eq 'explicit-list') {
    $null
  } elseif (-not [string]::IsNullOrWhiteSpace($baselineSha)) {
    ('{0}..{1}' -f $baselineSha, $headSha)
  } else {
    [string]$headSha
  }

  $candidateCommitShas = @()
  if ($historyMode -eq 'explicit-list') {
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($commitRef in $explicitCommitRefs) {
      $commitSha = Resolve-VIHistorySliceCommitSha -RepoRoot $repoRoot -Ref $commitRef -Label 'explicitCommits'
      if ($seen.Add($commitSha)) {
        $candidateCommitShas += $commitSha
      }
    }
  } else {
    $revListArgs = @('rev-list', '--reverse')
    switch ($historyMode) {
      'first-parent' { $revListArgs += '--first-parent' }
      'ancestry-path' { $revListArgs += '--ancestry-path' }
    }
    $revListArgs += $rangeExpression
    $revListArgs += '--'
    $revListArgs += $pathFilter
    $candidateCommitShas = @((Invoke-VIHistorySliceGit -RepoRoot $repoRoot -Arguments $revListArgs).Output |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  }

  $candidateCommitCount = @($candidateCommitShas).Count
  if ($null -ne $maxCommitCount -and $candidateCommitCount -gt $maxCommitCount) {
    throw ("Resolved VI history slice exceeds maxCommitCount ({0} > {1}) for target '{2}'." -f $candidateCommitCount, $maxCommitCount, $targetPath)
  }

  $selectedCommitShas = @($candidateCommitShas)
  if ($null -ne $maxPairs -and $selectedCommitShas.Count -gt $maxPairs) {
    $selectedCommitShas = @($selectedCommitShas | Select-Object -Last $maxPairs)
  }

  $commitEntries = @()
  for ($index = 0; $index -lt $selectedCommitShas.Count; $index++) {
    $commitSha = [string]$selectedCommitShas[$index]
    $candidateIndex = [Array]::IndexOf([string[]]$candidateCommitShas, $commitSha) + 1
    $parentSha = Resolve-VIHistorySliceFirstParentSha -RepoRoot $repoRoot -CommitSha $commitSha
    $commitEntries += [pscustomobject]@{
      index = $index + 1
      candidateIndex = $candidateIndex
      sha = $commitSha
      parentSha = if ([string]::IsNullOrWhiteSpace($parentSha)) { $null } else { [string]$parentSha }
      touchesPath = [bool](Test-VIHistorySliceCommitTouchesPath -RepoRoot $repoRoot -CommitSha $commitSha -PathFilter $pathFilter)
    }
  }

  $pairEntries = @()
  foreach ($commitEntry in @($commitEntries)) {
    if ([string]::IsNullOrWhiteSpace([string]$commitEntry.parentSha)) {
      continue
    }
    $pairEntries += [pscustomobject]@{
      index = $pairEntries.Count + 1
      baseSha = [string]$commitEntry.parentSha
      headSha = [string]$commitEntry.sha
      headCommitIndex = [int]$commitEntry.index
      targetPath = $targetPath
    }
  }

  $selectedPairTokens = @(
    $pairEntries | ForEach-Object {
      '{0}>{1}' -f [string]$_.baseSha, [string]$_.headSha
    }
  )
  $sliceDigest = Get-VIHistorySliceDigest `
    -RepoIdentity ([string]$repoIdentity.value) `
    -TargetPath $targetPath `
    -PathFilter $pathFilter `
    -HeadSha $headSha `
    -BaselineSha $baselineSha `
    -MergeBaseSha $mergeBaseSha `
    -BaselineMode $baselineMode `
    -HistoryMode $historyMode `
    -SelectionPolicyVersion $selectionPolicyVersion `
    -MaxPairs $maxPairs `
    -CandidateCommits @($candidateCommitShas) `
    -SelectedPairs @($selectedPairTokens)

  return [pscustomobject][ordered]@{
    schema = 'vi-history/slice-manifest@v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repoRoot = $repoRoot
    repoIdentity = [string]$repoIdentity.value
    repoIdentitySource = [string]$repoIdentity.source
    targetPath = $targetPath
    pathFilter = $pathFilter
    requested = [ordered]@{
      schema = 'vi-history/slice-selector@v1'
      repoPath = $repoPathInput
      targetPath = $targetPathInput
      pathFilter = $pathFilterInput
      headRef = $headRef
      baselineRef = if ([string]::IsNullOrWhiteSpace($baselineRef)) { $null } else { [string]$baselineRef }
      baselineMode = $baselineMode
      historyMode = $historyMode
      maxCommitCount = $maxCommitCount
      maxPairs = $maxPairs
      explicitCommits = @($explicitCommitRefs)
      repoIdentity = if ([string]::IsNullOrWhiteSpace([string]$repoIdentity.value)) { $null } else { [string]$repoIdentity.value }
      selectionPolicyVersion = [int]$selectionPolicyVersion
    }
    resolved = [ordered]@{
      headSha = $headSha
      baselineRefSha = if ([string]::IsNullOrWhiteSpace($baselineRefSha)) { $null } else { [string]$baselineRefSha }
      baselineSha = if ([string]::IsNullOrWhiteSpace($baselineSha)) { $null } else { [string]$baselineSha }
      mergeBaseSha = if ([string]::IsNullOrWhiteSpace($mergeBaseSha)) { $null } else { [string]$mergeBaseSha }
      baselineMode = $baselineMode
      historyMode = $historyMode
      rangeExpression = if ([string]::IsNullOrWhiteSpace($rangeExpression)) { $null } else { [string]$rangeExpression }
      candidateCommitCount = [int]$candidateCommitCount
      commitCount = [int]$commitEntries.Count
      pairCount = [int]$pairEntries.Count
      truncated = [bool]($candidateCommitCount -gt $commitEntries.Count)
    }
    candidateCommits = @($candidateCommitShas)
    commits = @($commitEntries)
    pairs = @($pairEntries)
    sliceDigest = $sliceDigest
  }
}

Export-ModuleMember -Function Resolve-VIHistorySliceManifest
