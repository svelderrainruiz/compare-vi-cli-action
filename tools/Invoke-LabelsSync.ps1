param(
  [switch]$Enforce,
  [switch]$Auto
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$labelsPath = '.github/labels.yml'
if (-not (Test-Path -LiteralPath $labelsPath -PathType Leaf)) {
  Write-Host '::notice::.github/labels.yml not found; skipping labels sync.'
  return
}

try {
  $yaml = Get-Content -LiteralPath $labelsPath -Raw
} catch {
  Write-Error "Failed to read .github/labels.yml: $_"
  exit 2
}

$matches = [regex]::Matches($yaml, '(?m)^\s*-\s*name:\s*(.+?)\s*$')
$names = @($matches | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
if (-not $names -or $names.Count -eq 0) {
  Write-Host '::notice::No labels defined in .github/labels.yml.'
  return
}

function Resolve-Repo {
  if ($env:GITHUB_REPOSITORY) { return $env:GITHUB_REPOSITORY }
  try {
    $remote = git remote get-url origin 2>$null
    if ($remote -match 'github\.com[:/](.+?/.+?)(?:\.git)?$') { return $Matches[1] }
  } catch {}
  return $null
}

$repo = Resolve-Repo
$token = $env:GITHUB_TOKEN

$mode = if ($Enforce) { 'Enforce' } elseif ($Auto -and $token) { 'Enforce' } else { 'Summary' }

if ($mode -eq 'Enforce' -and -not $token) {
  if ($Auto) {
    Write-Host '::notice::GITHUB_TOKEN not set; running labels sync in summary mode.'
    $mode = 'Summary'
  } else {
    Write-Error 'GITHUB_TOKEN not set; cannot enforce labels sync.'
    exit 2
  }
}

if (-not $repo) {
  $msg = 'Unable to determine repository; skipping labels sync.'
  if ($mode -eq 'Enforce') {
    Write-Error $msg
    exit 2
  } else {
    Write-Host ("::notice::{0}" -f $msg)
    return
  }
}

if (-not $token) {
  if ($mode -eq 'Enforce') {
    Write-Error 'GITHUB_TOKEN not set; cannot enforce labels sync.'
    exit 2
  }
  Write-Host '::notice::GITHUB_TOKEN not set; skipping GitHub label comparison.'
  Write-Host ("Defined in labels.yml: {0}" -f $names.Count)
  return
}

$headers = @{
  Authorization = "Bearer $token"
  Accept = 'application/vnd.github+json'
  'X-GitHub-Api-Version' = '2022-11-28'
}

try {
  $resp = Invoke-RestMethod -Method Get -Uri ("https://api.github.com/repos/{0}/labels?per_page=100" -f $repo) -Headers $headers
} catch {
  if ($mode -eq 'Enforce') {
    Write-Error ("Labels API call failed: {0}" -f $_.Exception.Message)
    exit 2
  } else {
    Write-Host ("::notice::Labels API call failed: {0}" -f $_.Exception.Message)
    return
  }
}

$existing = @($resp | ForEach-Object { $_.name })
$missing = @($names | Where-Object { $_ -and ($existing -notcontains $_) })

Write-Host ("Defined: {0} | Existing: {1} | Missing: {2}" -f $names.Count, $existing.Count, $missing.Count)
if ($missing.Count -gt 0) {
  Write-Host 'Missing:'
  foreach ($m in $missing) { Write-Host (' - ' + $m) }
  if ($mode -eq 'Enforce') {
    Write-Error 'Labels are out of sync.'
    exit 2
  }
} else {
  Write-Host 'Missing: none'
}
