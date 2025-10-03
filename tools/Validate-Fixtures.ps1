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
  Validates presence & basic integrity of canonical fixture VIs (Phase 1).
EXIT CODES
  0 ok | 2 missing | 3 untracked | 4 too small | 5 multiple issues
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
$missing = @(); $untracked = @(); $tooSmall = @()

foreach ($f in $fixtures) {
  if (-not (Test-Path -LiteralPath $f.Path)) { $missing += $f; continue }
  if ($tracked -notcontains $f.Name) { $untracked += $f; continue }
  $len = (Get-Item -LiteralPath $f.Path).Length
  if ($len -lt $MinBytes) { $tooSmall += @{ Name=$f.Name; Length=$len } }
}

if (-not $missing -and -not $untracked -and -not $tooSmall) { Emit info 'Fixture validation succeeded' 0; exit 0 }

$exit = 0
if ($missing) { $exit = 2; foreach ($m in $missing) { Emit error ("Missing canonical fixture {0}" -f $m.Name) 2 } }
if ($untracked) { $exit = if ($exit -eq 0) { 3 } else { 5 }; foreach ($u in $untracked) { Emit error ("Fixture {0} is not git-tracked" -f $u.Name) 3 } }
if ($tooSmall) { $exit = if ($exit -eq 0) { 4 } else { 5 }; foreach ($s in $tooSmall) { Emit error ("Fixture {0} length {1} < MinBytes {2}" -f $s.Name,$s.Length,$MinBytes) 4 } }

exit $exit
