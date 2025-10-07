param(
  [string]$ManifestPath = 'fixtures.manifest.json',
  [string]$ResultsDir = 'results/local',
  [string]$ExecJsonPath,
  [string]$BasePath,
  [string]$HeadPath,
  [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

 $root = Get-Location
 $source = 'manifest'
 $manifest = $null
 $manifestAvailable = $false
 $baseItem = $null
 $headItem = $null
 if ($ExecJsonPath) {
   if (-not (Test-Path -LiteralPath $ExecJsonPath)) { throw "Exec JSON not found: $ExecJsonPath" }
 } else {
   if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
 }
 if (Test-Path -LiteralPath $ManifestPath) {
   try {
     $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
     if ($manifest -and $manifest.items) { $manifestAvailable = $true }
   } catch {}
 }

 $tmp  = Join-Path $env:TEMP ("verify-fixture-"+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $tmp -Force | Out-Null
 $base = Join-Path $tmp 'base.vi'
 $head = Join-Path $tmp 'head.vi'
 if ($ExecJsonPath) {
   $source = 'execJson'
   $execIn = Get-Content -LiteralPath $ExecJsonPath -Raw | ConvertFrom-Json -ErrorAction Stop
   if (-not $execIn.base -or -not $execIn.head) { throw 'Exec JSON missing base/head fields' }
   Copy-Item -LiteralPath $execIn.base -Destination $base -Force
   Copy-Item -LiteralPath $execIn.head -Destination $head -Force
 } elseif ($BasePath -and $HeadPath) {
   $source = 'params'
   Copy-Item -LiteralPath $BasePath -Destination $base -Force
   Copy-Item -LiteralPath $HeadPath -Destination $head -Force
 } else {
   Copy-Item -LiteralPath (Join-Path $root $baseItem.path) -Destination $base -Force
   Copy-Item -LiteralPath (Join-Path $root $headItem.path) -Destination $head -Force
 }

$rd = Join-Path $root $ResultsDir
New-Item -ItemType Directory -Path $rd -Force | Out-Null
$execPath = Join-Path $rd 'compare-exec-verify.json'

Import-Module (Join-Path $root 'scripts/CompareVI.psm1') -Force
if ($ExecJsonPath) {
  # Do not re-run compare; use existing exec JSON (copy when different path)
  if ((Resolve-Path -LiteralPath $ExecJsonPath).Path -ne (Resolve-Path -LiteralPath $execPath -ErrorAction SilentlyContinue).Path) {
    Copy-Item -LiteralPath $ExecJsonPath -Destination $execPath -Force
  }
} else {
  Invoke-CompareVI -Base $base -Head $head -CompareExecJsonPath $execPath | Out-Null
}
$exec = Get-Content -LiteralPath $execPath -Raw | ConvertFrom-Json

$bytesBase = (Get-Item -LiteralPath $base).Length
$bytesHead = (Get-Item -LiteralPath $head).Length
$shaBase = (Get-FileHash -Algorithm SHA256 -LiteralPath $base).Hash.ToUpperInvariant()
$shaHead = (Get-FileHash -Algorithm SHA256 -LiteralPath $head).Hash.ToUpperInvariant()

# Optionally resolve matching manifest items by content hash when available
if ($manifestAvailable) {
  try {
    $baseItem = ($manifest.items | Where-Object { $_.sha256 -eq $shaBase })[-1]
    $headItem = ($manifest.items | Where-Object { $_.sha256 -eq $shaHead })[-1]
  } catch {}
}

$expectDiff = ($bytesBase -ne $bytesHead) -or ($shaBase -ne $shaHead)
$cliDiff    = [bool]$exec.diff
$ok = $false
$reason = ''
if ($expectDiff -and $cliDiff) { $ok = $true; $reason = 'diff-detected (agree: cli & manifest)' }
elseif ($expectDiff -and -not $cliDiff) { $ok = $false; $reason = 'diff-expected-from-manifest but cli reported no-diff' }
elseif (-not $expectDiff -and $cliDiff) { $ok = $false; $reason = 'cli reported diff but manifest suggests identical' }
else { $ok = $true; $reason = 'no-diff (agree: cli & manifest)' }

$summary = [ordered]@{
  schema = 'fixture-verify-summary/v1'
  generatedAt = (Get-Date).ToString('o')
  base = if ($baseItem) { $baseItem.path } else { Split-Path -Leaf $base }
  head = if ($headItem) { $headItem.path } else { Split-Path -Leaf $head }
  source = $source
  manifest = if ($manifestAvailable -and $baseItem -and $headItem) { [ordered]@{ baseBytes = $baseItem.bytes; headBytes=$headItem.bytes; baseSha=$baseItem.sha256; headSha=$headItem.sha256 } } else { $null }
  computed = [ordered]@{ baseBytes = $bytesBase; headBytes=$bytesHead; baseSha=$shaBase; headSha=$shaHead }
  cli = [ordered]@{ exitCode = $exec.exitCode; diff = $cliDiff; duration_s = $exec.duration_s; command = $exec.command }
  expectDiff = $expectDiff
  ok = $ok
  reason = $reason
}

$sumPath = Join-Path $rd 'fixture-verify-summary.json'
$summary | ConvertTo-Json -Depth 6 | Out-File -FilePath $sumPath -Encoding UTF8

if ($VerboseOutput) {
  Write-Host ("Fixture verify: ok={0} reason={1}" -f $ok,$reason)
  Write-Host ("Summary: {0}" -f $sumPath)
}

if (-not $ok) { exit 6 } else { exit 0 }
