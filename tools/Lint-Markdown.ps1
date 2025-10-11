param(
  [switch]$All,
  [string]$BaseRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-GitRoot {
  $root = (& git rev-parse --show-toplevel 2>$null).Trim()
  if (-not $root) {
    throw 'Unable to determine repository root (is git installed?).'
  }
  return $root
}

function Resolve-MergeBase {
  param([string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if (-not $candidate) { continue }
    $rawRef = (& git rev-parse --verify $candidate 2>$null)
    if (-not $rawRef) { continue }
    $ref = $rawRef.Trim()
    if (-not $ref) { continue }
    $mergeBase = (& git merge-base HEAD $ref 2>$null).Trim()
    if ($mergeBase) {
      return $mergeBase
    }
    return $ref
  }
  return $null
}

function Get-ChangedMarkdownFiles {
  param([string]$Base)
  $files = @()
  if ($Base) {
    $files += (& git diff --name-only --diff-filter=ACMRTUXB "$Base..HEAD" 2>$null)
  }
  $files += (& git diff --name-only --diff-filter=ACMRTUXB HEAD 2>$null)
  $files += (& git diff --name-only --cached --diff-filter=ACMRTUXB 2>$null)
  $files += (& git ls-files --others --exclude-standard '*.md' 2>$null)
  return ($files | Where-Object { $_ -and $_.ToLower().EndsWith('.md') } | Sort-Object -Unique)
}

function Get-AllMarkdownFiles {
  return ((& git ls-files '*.md' 2>$null) | Where-Object { $_ } | Sort-Object -Unique)
}

function Invoke-Markdownlint {
  param([string[]]$Files)
  $npx = Get-Command -Name 'npx' -ErrorAction Stop
  $args = @('--no-install', 'markdownlint-cli2', '--config', '.markdownlint.jsonc')
  $args += $Files
  $output = & $npx.Source @args 2>&1
  $exitCode = $LASTEXITCODE
  if ($output) {
    foreach ($entry in $output) {
      $text = [string]$entry
      $text = $text.TrimEnd()
      if ($text -ne '') {
        Write-Host $text
      }
    }
  }
  if ($exitCode -eq 0) {
    return 0
  }

  $rules = @()
  foreach ($entry in $output) {
    $line = [string]$entry
    if (-not $line) { continue }
    if ($line -match 'MD\d+') {
      $rules += $Matches[0]
    }
  }
  $nonWarningRules = ($rules | Sort-Object -Unique) | Where-Object { $_ -notin @('MD041','MD013') }
  if (-not $nonWarningRules) {
    Write-Warning 'Only MD041/MD013 violations detected; treating as a warning.'
    return 0
  }
  return [int]$exitCode
}

$repoRoot = Resolve-GitRoot
Push-Location $repoRoot
try {
  $candidateRefs = @()
  if ($BaseRef) { $candidateRefs += $BaseRef }
  if ($env:GITHUB_BASE_SHA) { $candidateRefs += $env:GITHUB_BASE_SHA }
  if ($env:GITHUB_BASE_REF) { $candidateRefs += "origin/$($env:GITHUB_BASE_REF)" }
  $candidateRefs += 'origin/develop', 'origin/main', 'HEAD~1'
  $mergeBase = $null
  if (-not $All) {
    $mergeBase = Resolve-MergeBase -Candidates $candidateRefs
  }

  $markdownFiles = if ($All) {
    Get-AllMarkdownFiles
  } else {
    Get-ChangedMarkdownFiles -Base $mergeBase
  }

  if (-not $markdownFiles -or $markdownFiles.Count -eq 0) {
    Write-Host 'No Markdown files to lint.'
    exit 0
  }

  # Scoped suppressions for known large/generated files until backlog is addressed
  $suppressed = @(
    'CHANGELOG.md',
    'fixture-summary.md'
  )
  $filesToLint = $markdownFiles | Where-Object { $suppressed -notcontains $_ }

  Write-Host ("Linting {0} Markdown file(s)." -f $filesToLint.Count)
  $result = Invoke-Markdownlint -Files $filesToLint
  if ($result -ne 0) {
    exit $result
  }
} finally {
  Pop-Location
}
