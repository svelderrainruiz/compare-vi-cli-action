param(
  [Parameter(Mandatory = $true)][string]$ViName,
  [string]$Branch = 'HEAD',
  [int]$MaxPairs = 20,
  [string]$ResultsDir = 'tests/results/ref-compare-history',
  [string]$LvCompareArgs,
  [string]$InvokeScriptPath,
  [switch]$FailOnDiff,
  [switch]$IncludeIdenticalPairs,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$IgnoreNonZero
  )

  $result = & git @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if (-not $IgnoreNonZero -and $exitCode -ne 0) {
    throw "git $($Arguments -join ' ') failed: $result"
  }
  if ($result -is [System.Array]) {
    $lines = @($result)
  } else {
    $lines = ($result -split "`r?`n")
  }
  return @($lines | Where-Object { $_ -ne $null })
}

function Split-ArgString {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
  $errors = $null
  $tokens = [System.Management.Automation.PSParser]::Tokenize($Value, [ref]$errors)
  $accepted = @('CommandArgument', 'String', 'Number', 'CommandParameter')
  $list = @()
  foreach ($token in $tokens) {
    if ($accepted -contains $token.Type) { $list += $token.Content }
  }
  return @($list | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ItemCount {
  param($Value)
  if ($null -eq $Value) { return 0 }
  if ($Value -is [System.Collections.IDictionary]) { return $Value.Count }
  if ($Value -is [System.Collections.ICollection]) { return $Value.Count }
  if ($Value -is [string]) { return ([string]::IsNullOrWhiteSpace($Value)) ? 0 : 1 }
  return (@($Value) | Measure-Object).Count
}

function Resolve-ViRelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$ViName,
    [Parameter(Mandatory = $true)][string[]]$Refs
  )

  $viLeaf = $ViName.Trim()
  if ([string]::IsNullOrWhiteSpace($viLeaf)) { throw "VI name cannot be empty." }
  $viLeafLower = $viLeaf.ToLowerInvariant()
  $refMatches = [ordered]@{}
  $pathLookup = @{}

  foreach ($ref in $Refs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    $pathsForRef = @()
    $ls = Invoke-Git -Arguments @('ls-tree', '-r', '--name-only', $ref)
    foreach ($entry in @($ls)) {
      if (-not $entry) { continue }
      $leaf = (Split-Path $entry -Leaf)
      if ($leaf -and $leaf.ToLowerInvariant() -eq $viLeafLower) {
        $pathsForRef += $entry
        $lower = $entry.ToLowerInvariant()
        if (-not $pathLookup.ContainsKey($lower)) { $pathLookup[$lower] = $entry }
      }
    }
    if ($pathsForRef.Count -gt 0) { $refMatches[$ref] = $pathsForRef }
  }

  if ($refMatches.Count -eq 0) {
    throw "VI '$ViName' not found in refs: $($Refs -join ', ')"
  }

  $lowerLists = @()
  foreach ($pair in $refMatches.GetEnumerator()) {
    $lowerLists += ,(@($pair.Value | ForEach-Object { $_.ToLowerInvariant() }))
  }

  $commonLower = $lowerLists[0]
  for ($i = 1; $i -lt $lowerLists.Count; $i++) {
    $current = $lowerLists[$i]
    $commonLower = @($commonLower | Where-Object { $current -contains $_ })
  }

  $commonLower = @($commonLower | Select-Object -Unique)
  $commonPaths = @($commonLower | ForEach-Object { $pathLookup[$_] }) | Where-Object { $_ }
  $allLower = @($pathLookup.Keys)
  $allPaths = @($allLower | ForEach-Object { $pathLookup[$_] }) | Where-Object { $_ }

  $pathScore = {
    param([string]$PathValue)
    $score = 0
    if ($PathValue -match '^tmp-commit') { $score += 200 }
    elseif ($PathValue -match '^tmp') { $score += 150 }
    if ($PathValue -match '^tests/') { $score += 100 }
    $depth = (($PathValue -split '/').Count - 1)
    if ($depth -gt 0) { $score += ($depth * 25) }
    $score += [Math]::Min([int]$PathValue.Length, 500) / 10
    return $score
  }

  $candidates = @($commonPaths)
  if ($candidates.Count -eq 0) { $candidates = @($allPaths) }
  if ($candidates.Count -eq 0) {
    throw "Unable to resolve VI path for '$ViName'."
  }

  $ordered = $candidates | Sort-Object @{ Expression = { & $pathScore $_ } }, @{ Expression = { $_ } }
  $chosen = $ordered | Select-Object -First 1
  if (-not $chosen) { throw "Unable to resolve VI path for '$ViName'." }
  if ($candidates.Count -gt 1) {
    Write-Verbose ("[Compare-VIHistory] Multiple candidates for '{0}'; selected '{1}'" -f $ViName, $chosen)
  }
  return $chosen
}

$repoRoot = (Get-Location).Path
$compareScript = Join-Path $repoRoot 'tools' 'Compare-RefsToTemp.ps1'
if (-not (Test-Path -LiteralPath $compareScript -PathType Leaf)) {
  throw "Compare-RefsToTemp.ps1 not found at expected path: $compareScript"
}

Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree') > $null

$resolvedPath = Resolve-ViRelativePath -ViName $ViName -Refs @($Branch)
Write-Verbose "Resolved VI path: $resolvedPath"

$logArgs = @('log', '--follow', '--format=%H', $Branch, '--', $resolvedPath)
$commitList = @(Invoke-Git -Arguments $logArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Write-Verbose ("Commit hashes (newest first): {0}" -f ($commitList -join ', '))
$commitCount = Get-ItemCount $commitList
if (-not $Quiet) { Write-Host "Commit count detected: $commitCount" }
if ($commitCount -lt 2) {
  Write-Host "Only one commit touches $ViName; nothing to compare."
  exit 0
}

if ($MaxPairs -lt 1) { $MaxPairs = 1 }
$desiredCount = [Math]::Min((Get-ItemCount $commitList), $MaxPairs + 1)
$commitTotal = Get-ItemCount $commitList
if (-not $Quiet) {
  Write-Host "Found $commitTotal commits touching $ViName (using last $desiredCount for history scan)."
}
$recentCommits = @($commitList | Select-Object -Last $desiredCount)
[array]::Reverse($recentCommits)
$pairs = @()
$recentCommitCount = Get-ItemCount $recentCommits
Write-Verbose ("Recent commit window (oldest->newest): {0}" -f ($recentCommits -join ', '))
Write-Verbose ("Recent commit count: {0}" -f $recentCommitCount)
for ($i = 0; $i -lt $recentCommitCount - 1; $i++) {
  $pairs += [pscustomobject]@{
    Index = $i
    RefA  = $recentCommits[$i]
    RefB  = $recentCommits[$i + 1]
  }
}

$pairCount = Get-ItemCount $pairs
if (-not $Quiet) { Write-Host "Generated pair count: $pairCount" }
if ($pairCount -eq 0) {
  Write-Host "No commit pairs found for $ViName."
  exit 0
}

$resultsRoot = if ([System.IO.Path]::IsPathRooted($ResultsDir)) { $ResultsDir } else { Join-Path $repoRoot $ResultsDir }
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null

$flagTokens = Split-ArgString -Value $LvCompareArgs
$summaryItems = @()
$hadFailure = $false
$markdownRows = @()

function Get-BlobIdForPath {
  param(
    [Parameter(Mandatory = $true)][string]$Ref,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $output = Invoke-Git -Arguments @('rev-parse', "$Ref`:$Path") -IgnoreNonZero
  if (-not $output) { return $null }
  $first = ($output | Select-Object -First 1)
  if (-not $first) { return $null }
  return $first.Trim()
}

foreach ($pair in $pairs) {
  $refA = $pair.RefA
  $refB = $pair.RefB
  $index = $pair.Index
  $pairLabel = "{0:D2}-{1:D2}" -f $index, ($index + 1)

  $pathA = $null
  $pathB = $null
  $pathError = $null
  try {
    $pathA = Resolve-ViRelativePath -ViName $ViName -Refs @($refA)
  } catch {
    $pathError = "Ref $refA missing ${ViName}: $($_.Exception.Message)"
  }
  if (-not $pathError) {
    try {
      $pathB = Resolve-ViRelativePath -ViName $ViName -Refs @($refB)
    } catch {
      $pathError = "Ref $refB missing ${ViName}: $($_.Exception.Message)"
    }
  }
  if ($pathError) {
    $summaryItems += [ordered]@{
      refA             = $refA
      refB             = $refB
      pair             = $pairLabel
      skippedIdentical = $false
      skippedMissing   = $true
      skipReason       = $pathError
      diff             = $false
      exitCode         = $null
      summaryJson      = $null
      reportHtml       = $null
      highlights       = @()
      blobA            = $null
      blobB            = $null
      lvcompare        = $null
    }
    $markdownRows += "| $pairLabel | Skipped (missing VI) | - | $pathError |"
    continue
  }
  $blobA = Get-BlobIdForPath -Ref $refA -Path $pathA
  $blobB = Get-BlobIdForPath -Ref $refB -Path $pathB
  $identical = ($blobA -ne $null -and $blobA -eq $blobB)

  if ($identical -and -not $IncludeIdenticalPairs) {
    $summaryItems += [ordered]@{
      refA              = $refA
      refB              = $refB
      pair              = $pairLabel
      skippedIdentical  = $true
      skippedMissing    = $false
      skipReason        = $null
      diff              = $false
      exitCode          = $null
      summaryJson       = $null
      reportHtml        = $null
      highlights        = @()
      blobA             = $blobA
      blobB             = $blobB
      lvcompare         = $null
    }
    $markdownRows += "| $pairLabel | Skipped (identical) | - | - |"
    continue
  }

  $outName = ('{0}-{1}' -f ($ViName -replace '[^A-Za-z0-9._-]+', '_'), $pairLabel)
  $args = @(
    '-NoLogo', '-NoProfile', '-File', $compareScript,
    '-ViName', $ViName,
    '-RefA', $refA,
    '-RefB', $refB,
    '-ResultsDir', $resultsRoot,
    '-OutName', $outName,
    '-Detailed',
    '-RenderReport',
    '-Quiet:$false'
  )
  if ($InvokeScriptPath) {
    $args += '-InvokeScriptPath'
    $args += $InvokeScriptPath
  }
  if ($flagTokens -and $flagTokens.Length -gt 0) {
    $args += '-LvCompareArgs'
    $args += ($flagTokens -join ' ')
  }
  $args += (if ($FailOnDiff) { '-FailOnDiff:$true' } else { '-FailOnDiff:$false' })

  if (-not $Quiet) {
    Write-Host "Comparing $ViName for commits $refA -> $refB (pair $pairLabel)..."
  }

  $proc = Start-Process -FilePath 'pwsh' -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
  $exitCode = $proc.ExitCode

  $compareSummaryPath = Join-Path $resultsRoot ("$outName-summary.json")
  $compareReportPath = Join-Path $resultsRoot ("$outName-artifacts")
  $summaryJson = $null
  $cliInfo = $null
  $diffResult = $null
  $highlights = @()
  $reportFile = $null

  if (Test-Path -LiteralPath $compareSummaryPath) {
    $summaryJson = Get-Content -LiteralPath $compareSummaryPath -Raw | ConvertFrom-Json -Depth 8
    $diffResult = $summaryJson.cli.diff
    $cliInfo = $summaryJson.cli
    if ($summaryJson.out -and $summaryJson.out.reportHtml) {
      $reportFile = $summaryJson.out.reportHtml
    }
    if ($summaryJson.cli -and $summaryJson.cli.highlights) {
      $highlights = @($summaryJson.cli.highlights)
    }
  }

  if ($exitCode -ne 0 -and -not ($FailOnDiff -and $diffResult)) {
    $hadFailure = $true
  }

  $summaryItems += [ordered]@{
    refA             = $refA
    refB             = $refB
    pair             = $pairLabel
    skippedIdentical = $false
    skippedMissing   = $false
    skipReason       = $null
    diff             = [bool]$diffResult
    exitCode         = $exitCode
    summaryJson      = $compareSummaryPath
    reportHtml       = $reportFile
    highlights       = $highlights
    blobA            = $blobA
    blobB            = $blobB
    lvcompare        = $cliInfo
  }

  $status = if ($diffResult) { 'Diff' } elseif ($exitCode -eq 0) { 'No diff' } else { "Error ($exitCode)" }
  $highlightText = if (Get-ItemCount $highlights -gt 0) { ($highlights | Select-Object -First 2) -join '; ' } else { '' }
  $mkNotes = if ($highlightText) { $highlightText } elseif ($reportFile) { (Split-Path $reportFile -Leaf) } else { '' }
  $markdownRows += "| $pairLabel | $status | $exitCode | $mkNotes |"
}

$historySummary = [ordered]@{
  schema         = 'vi-history-compare/v1'
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  viName         = $ViName
  branch         = $Branch
  resolvedPath   = $resolvedPath
  maxPairs       = $MaxPairs
  lvcompareArgs  = $flagTokens
  includeIdentical = [bool]$IncludeIdenticalPairs
  resultsDir     = $resultsRoot
  pairs          = $summaryItems
}

$summaryPath = Join-Path $resultsRoot 'history-summary.json'
$historySummary | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $summaryPath -Encoding utf8

if (-not $Quiet) {
  Write-Host "History summary written to $summaryPath"
}

if ($env:GITHUB_STEP_SUMMARY) {
  $lines = @(
    '### VI History Compare',
    '',
    "| Pair | Outcome | Exit | Notes |",
    "|------|---------|------|-------|"
  )
  if (Get-ItemCount $markdownRows -gt 0) {
    $lines += $markdownRows
  } else {
    $lines += "| - | - | - | - |"
  }
  $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

if ($hadFailure) {
  throw "One or more comparisons failed. See $resultsRoot for details."
}
