param(
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(Mandatory=$true)][string]$RefA,
  [Parameter(Mandatory=$true)][string]$RefB,
  [string]$ResultsDir = 'tests/results/ref-compare',
  [string]$OutName = 'vi1_vs_vi1',
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure git present
try { git --version | Out-Null } catch { throw 'git is required on PATH to fetch file content at refs.' }

$repoRoot = (Get-Location).Path
$absPath = Join-Path $repoRoot $Path
if (-not (Test-Path -LiteralPath $absPath)) { throw "Path not found in repo: $Path" }

function Get-FileAtRef([string]$ref,[string]$relPath,[string]$dest){
  $dir = Split-Path -Parent $dest
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  # Resolve blob id for the file at the ref
  $ls = & git ls-tree -r $ref -- $relPath 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $ls) { throw "git ls-tree failed to find $relPath at $ref" }
  $blob = $null
  foreach ($line in $ls) {
    $m = [regex]::Match($line, '^[0-9]+\s+blob\s+([0-9a-fA-F]{40})\s+\t')
    if ($m.Success) { $blob = $m.Groups[1].Value; break }
    $parts = $line -split '\s+'
    if ($parts.Count -ge 3 -and $parts[1] -eq 'blob') { $blob = $parts[2]; break }
  }
  if (-not $blob) { throw "Could not parse blob id for $relPath at $ref" }
  # Stream blob contents to file
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'git'
  foreach($a in @('cat-file','-p', $blob)) { [void]$psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $fs = [System.IO.File]::Open($dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git cat-file failed for $blob (code=$($p.ExitCode))" }
}

# Create temp folder and write base/head
$tmp = Join-Path $env:TEMP ("refcmp-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$base = Join-Path $tmp 'Base.vi'
$head = Join-Path $tmp 'Head.vi'

Get-FileAtRef -ref $RefA -relPath $Path -dest $base
Get-FileAtRef -ref $RefB -relPath $Path -dest $head

$rd = if ([System.IO.Path]::IsPathRooted($ResultsDir)) { $ResultsDir } else { Join-Path $repoRoot $ResultsDir }
New-Item -ItemType Directory -Path $rd -Force | Out-Null
$execPath = Join-Path $rd ("$OutName-exec.json")
$sumPath  = Join-Path $rd ("$OutName-summary.json")

# Compute expected diff by content (bytes/sha)
$bytesBase = (Get-Item -LiteralPath $base).Length
$bytesHead = (Get-Item -LiteralPath $head).Length
$shaBase = (Get-FileHash -Algorithm SHA256 -LiteralPath $base).Hash.ToUpperInvariant()
$shaHead = (Get-FileHash -Algorithm SHA256 -LiteralPath $head).Hash.ToUpperInvariant()
$expectDiff = ($bytesBase -ne $bytesHead) -or ($shaBase -ne $shaHead)

# Run CompareVI to produce exec json
Import-Module (Join-Path $repoRoot 'scripts/CompareVI.psm1') -Force
Invoke-CompareVI -Base $base -Head $head -CompareExecJsonPath $execPath | Out-Null
$exec = Get-Content -LiteralPath $execPath -Raw | ConvertFrom-Json

# Summarize
$sum = [ordered]@{
  schema = 'ref-compare-summary/v1'
  generatedAt = (Get-Date).ToString('o')
  path = $Path
  refA = $RefA
  refB = $RefB
  temp = $tmp
  out = [ordered]@{ execJson = (Resolve-Path $execPath).Path }
  computed = [ordered]@{ baseBytes=$bytesBase; headBytes=$bytesHead; baseSha=$shaBase; headSha=$shaHead; expectDiff=$expectDiff }
  cli = [ordered]@{ exitCode = $exec.exitCode; diff = [bool]$exec.diff; duration_s = $exec.duration_s; command = $exec.command }
}
$sum | ConvertTo-Json -Depth 6 | Out-File -FilePath $sumPath -Encoding UTF8

if (-not $Quiet) {
  Write-Host "Ref compare complete: $Path ($RefA vs $RefB)"
  Write-Host "- Exec: $execPath"
  Write-Host "- Summary: $sumPath"
  Write-Host ("- ExpectDiff={0} | cli.diff={1} | exitCode={2}" -f $expectDiff,([bool]$exec.diff),$exec.exitCode)
}

exit 0
