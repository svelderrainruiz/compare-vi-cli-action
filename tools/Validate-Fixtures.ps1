${ErrorActionPreference} = 'Stop'
# Manual argument parsing (avoid param binding edge cases under certain hosts)
$MinBytes = 32
$QuietOutput = $false
for ($i=0; $i -lt $args.Length; $i++) {
  switch -Regex ($args[$i]) {
    '^-MinBytes$' { if ($i + 1 -lt $args.Length) { $i++; [int]$MinBytes = $args[$i] }; continue }
    '^-Quiet(Output)?$' { $QuietOutput = $true; continue }
  }
}

<#
SYNOPSIS
  Validates canonical fixture VIs (Phase 1 + Phase 2 hash manifest).
EXIT CODES
  0 ok | 2 missing | 3 untracked | 4 too small | 5 multiple issues | 6 hash mismatch | 7 manifest error
#>

## Quiet flag already normalized above

function Emit {
  param([string]$Level,[string]$Msg,[int]$Code)
  if ($QuietOutput -and $Level -ne 'error') { return }
  $fmt = '[fixture] level={0} code={1} message="{2}"'
  Write-Host ($fmt -f $Level,$Code,$Msg)
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
$fixtures = @(
  @{ Name='VI1.vi'; Path=(Join-Path $repoRoot 'VI1.vi') }
  @{ Name='VI2.vi'; Path=(Join-Path $repoRoot 'VI2.vi') }
)
$tracked = (& git ls-files) -split "`n" | Where-Object { $_ }
$missing = @(); $untracked = @(); $tooSmall = @(); $hashMismatch = @(); $manifestError = $false

# Phase 2: Load manifest if present
$manifestPath = Join-Path $repoRoot 'fixtures.manifest.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (-not $manifest.items) { throw 'Missing items array' }
  } catch {
    Emit error ("Manifest read/parse failure: {0}" -f $_.Exception.Message) 7
    $manifestError = $true
  }
}

$manifestIndex = @{}
if ($manifest -and $manifest.items) {
  foreach ($it in $manifest.items) { $manifestIndex[$it.path] = $it }
}

foreach ($f in $fixtures) {
  if (-not (Test-Path -LiteralPath $f.Path)) { $missing += $f; continue }
  if ($tracked -notcontains $f.Name) { $untracked += $f; continue }
  $len = (Get-Item -LiteralPath $f.Path).Length
  if ($len -lt $MinBytes) { $tooSmall += @{ Name=$f.Name; Length=$len } }
  # Hash verification (Phase 2) when manifest present
  if ($manifest -and $manifestIndex.ContainsKey($f.Name)) {
    try {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Path).Hash.ToUpperInvariant()
      $expected = ($manifestIndex[$f.Name].sha256).ToUpperInvariant()
      if ($hash -ne $expected) { $hashMismatch += @{ Name=$f.Name; Actual=$hash; Expected=$expected } }
    } catch {
      Emit error ("Hash computation failed for {0}: {1}" -f $f.Name,$_.Exception.Message) 7
      $manifestError = $true
    }
  }
}

# Commit message token override
$allowOverride = $false
try {
  $headSha = (& git rev-parse -q HEAD 2>$null).Trim()
  if ($headSha) {
    $msg = (& git log -1 --pretty=%B 2>$null)
    if ($msg -match '\[fixture-update\]') { $allowOverride = $true }
  }
} catch { }

if ($allowOverride -and $hashMismatch) {
  Emit info 'Hash mismatches ignored due to [fixture-update] token' 0
  $hashMismatch = @() # neutralize
}

if (-not $missing -and -not $untracked -and -not $tooSmall -and -not $manifestError -and -not $hashMismatch) {
  Emit info 'Fixture validation succeeded' 0; exit 0 }

$exit = 0
if ($missing) { $exit = 2; foreach ($m in $missing) { Emit error ("Missing canonical fixture {0}" -f $m.Name) 2 } }
if ($untracked) { $exit = if ($exit -eq 0) { 3 } else { 5 }; foreach ($u in $untracked) { Emit error ("Fixture {0} is not git-tracked" -f $u.Name) 3 } }
if ($tooSmall) { $exit = if ($exit -eq 0) { 4 } else { 5 }; foreach ($s in $tooSmall) { Emit error ("Fixture {0} length {1} < MinBytes {2}" -f $s.Name,$s.Length,$MinBytes) 4 } }
if ($manifestError) { $exit = if ($exit -eq 0) { 7 } else { 5 } }
if ($hashMismatch) {
  $exit = if ($exit -eq 0) { 6 } else { 5 }
  foreach ($h in $hashMismatch) { Emit error ("Fixture {0} hash mismatch (actual {1} expected {2})" -f $h.Name,$h.Actual,$h.Expected) 6 }
}

exit $exit
