param(
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(Mandatory=$true)][string]$RefA,
  [Parameter(Mandatory=$true)][string]$RefB,
  [string]$ResultsDir = 'tests/results/ref-compare',
  [string]$OutName = 'vi1_vs_vi1',
  [switch]$Quiet,
  [switch]$Detailed,
  [switch]$RenderReport,
  [string]$LvCompareArgs,
  [switch]$ReplaceFlags,
  [string]$LvComparePath,
  [string]$LabVIEWExePath,
  [string]$InvokeScriptPath,
  [switch]$FailOnDiff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { git --version | Out-Null } catch { throw 'git is required on PATH to fetch file content at refs.' }

$repoRoot = (Get-Location).Path
$absPath = Join-Path $repoRoot $Path
if (-not (Test-Path -LiteralPath $absPath)) { throw "Path not found in repo: $Path" }

function Split-ArgString {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
  $errors = $null
  $tokens = [System.Management.Automation.PSParser]::Tokenize($Value, [ref]$errors)
  $accepted = @('CommandArgument','String','Number','CommandParameter')
  $list = @()
  foreach ($token in $tokens) {
    if ($accepted -contains $token.Type) { $list += $token.Content }
  }
  return @($list | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Normalize-ExistingPath {
  param([string]$Candidate)
  if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
  try { return (Resolve-Path -LiteralPath $Candidate -ErrorAction Stop).Path } catch { return $Candidate }
}

function Get-FileAtRef([string]$ref,[string]$relPath,[string]$dest){
  $dir = Split-Path -Parent $dest
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
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

function Invoke-PwshProcess {
  param(
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [switch]$QuietOutput
  )

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'pwsh'
  foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $repoRoot
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  if (-not $QuietOutput) {
    if ($stdout) { Write-Host $stdout }
    if ($stderr) { Write-Host $stderr }
  } elseif ($proc.ExitCode -ne 0) {
    if ($stdout) { Write-Host $stdout }
    if ($stderr) { Write-Host $stderr }
  }
  [pscustomobject]@{
    ExitCode = $proc.ExitCode
    StdOut   = $stdout
    StdErr   = $stderr
  }
}

$detailRequested = $Detailed.IsPresent -or $RenderReport.IsPresent
$flagTokens = Split-ArgString -Value $LvCompareArgs
$lvComparePathResolved = Normalize-ExistingPath $LvComparePath
$labviewExeResolved    = Normalize-ExistingPath $LabVIEWExePath
$invokeScriptResolved  = $null
if ($detailRequested -or $InvokeScriptPath) {
  if (-not $InvokeScriptPath) { $InvokeScriptPath = Join-Path (Join-Path $repoRoot 'tools') 'Invoke-LVCompare.ps1' }
  $invokeScriptResolved = Normalize-ExistingPath $InvokeScriptPath
  if (-not (Test-Path -LiteralPath $invokeScriptResolved -PathType Leaf)) {
    throw "Invoke-LVCompare script not found: $invokeScriptResolved"
  }
}
$renderReportRequested = $RenderReport.IsPresent -or $detailRequested

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
$artifactDir = $null
if ($detailRequested) {
  $artifactDir = Join-Path $rd ("$OutName-artifacts")
  New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
}

$bytesBase = (Get-Item -LiteralPath $base).Length
$bytesHead = (Get-Item -LiteralPath $head).Length
$shaBase = (Get-FileHash -Algorithm SHA256 -LiteralPath $base).Hash.ToUpperInvariant()
$shaHead = (Get-FileHash -Algorithm SHA256 -LiteralPath $head).Hash.ToUpperInvariant()
$expectDiff = ($bytesBase -ne $bytesHead) -or ($shaBase -ne $shaHead)

Import-Module (Join-Path (Join-Path $repoRoot 'scripts') 'CompareVI.psm1') -Force

$cliExit = $null
$cliDiff = $false
$cliCommand = $null
$cliPath = $null
$cliDurationSeconds = $null
$cliDurationNanoseconds = $null
$cliArgsRecorded = @()
$cliArtifacts = $null
$cliHighlights = @()
$cliStdoutPreview = @()
$detailPaths = [ordered]@{}

if ($detailRequested) {
  $invokeArgs = @('-NoLogo','-NoProfile','-File', $invokeScriptResolved, '-BaseVi', $base, '-HeadVi', $head, '-OutputDir', $artifactDir, '-Quiet')
  if ($renderReportRequested) { $invokeArgs += '-RenderReport' }
  if ($lvComparePathResolved) { $invokeArgs += '-LVComparePath'; $invokeArgs += $lvComparePathResolved }
  if ($labviewExeResolved) { $invokeArgs += '-LabVIEWExePath'; $invokeArgs += $labviewExeResolved }
  if ($flagTokens.Count -gt 0) {
    $invokeArgs += '-Flags'
    foreach ($token in $flagTokens) { $invokeArgs += $token }
  }
  if ($ReplaceFlags) { $invokeArgs += '-ReplaceFlags' }

  $invokeResult = Invoke-PwshProcess -Arguments $invokeArgs -QuietOutput:$Quiet
  $capturePath = Join-Path $artifactDir 'lvcompare-capture.json'
  $stdoutPath  = Join-Path $artifactDir 'lvcompare-stdout.txt'
  $stderrPath  = Join-Path $artifactDir 'lvcompare-stderr.txt'
  $reportPath  = Join-Path $artifactDir 'compare-report.html'
  $imagesDir   = Join-Path $artifactDir 'cli-images'

  $capture = $null
  if (Test-Path -LiteralPath $capturePath) {
    $capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json -Depth 8
  }
  if (-not $capture) {
    throw "lvcompare-capture.json not produced (exit code $($invokeResult.ExitCode)). Inspect $artifactDir for details."
  }

  $cliExit = if ($capture.exitCode -ne $null) { [int]$capture.exitCode } else { [int]$invokeResult.ExitCode }
  $cliDiff = ($cliExit -eq 1)
  $cliCommand = if ($capture.command) { [string]$capture.command } else { $null }
  $cliPath = if ($capture.cliPath) { [string]$capture.cliPath } else { $lvComparePathResolved }
  if ($capture.seconds -ne $null) {
    $cliDurationSeconds = [double]$capture.seconds
    $cliDurationNanoseconds = [long]([Math]::Round($cliDurationSeconds * 1e9))
  }
  if ($capture.args) { $cliArgsRecorded = @($capture.args | ForEach-Object { [string]$_ }) }

  if ($cliExit -notin @(0,1)) {
    throw "LVCompare failed with exit code $cliExit. See $capturePath for details."
  }

  if ($capture.PSObject.Properties['environment'] -and $capture.environment -and $capture.environment.PSObject.Properties['cli']) {
    $cliNode = $capture.environment.cli
    if ($cliNode.PSObject.Properties['artifacts'] -and $cliNode.artifacts) {
      $artifactSummary = [ordered]@{}
      foreach ($prop in $cliNode.artifacts.PSObject.Properties) {
        if ($prop.Name -eq 'images' -and $prop.Value) {
          $images = @()
          foreach ($img in @($prop.Value)) {
            if (-not $img) { continue }
            $images += [ordered]@{
              index      = $img.index
              mimeType   = $img.mimeType
              byteLength = $img.byteLength
              savedPath  = $img.savedPath
            }
          }
          if ($images.Count -gt 0) { $artifactSummary.images = $images }
        } else {
          $artifactSummary[$prop.Name] = $prop.Value
        }
      }
      if ($artifactSummary.Count -gt 0) { $cliArtifacts = [pscustomobject]$artifactSummary }
    }
  }

  if (Test-Path -LiteralPath $stdoutPath) {
    $stdoutLines = Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
    if ($stdoutLines) {
      $cliStdoutPreview = @($stdoutLines | Select-Object -First 10)
      foreach ($line in $stdoutLines) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -match '(?i)(block\s+diagram|front\s+panel|vi\s+attribute|connector\s+pane|terminal)') {
          $cliHighlights += $trimmed
        }
      }
      $cliHighlights = @($cliHighlights | Select-Object -Unique | Select-Object -First 20)
    }
  }

  if (Test-Path -LiteralPath $capturePath) { $detailPaths.captureJson = (Resolve-Path -LiteralPath $capturePath).Path }
  if (Test-Path -LiteralPath $stdoutPath)  { $detailPaths.stdout       = (Resolve-Path -LiteralPath $stdoutPath).Path }
  if (Test-Path -LiteralPath $stderrPath)  { $detailPaths.stderr       = (Resolve-Path -LiteralPath $stderrPath).Path }
  if (Test-Path -LiteralPath $reportPath)  { $detailPaths.reportHtml   = (Resolve-Path -LiteralPath $reportPath).Path }
  if (Test-Path -LiteralPath $imagesDir)   { $detailPaths.imagesDir    = (Resolve-Path -LiteralPath $imagesDir).Path }

  $execObject = [ordered]@{
    schema      = 'compare-exec/v1'
    generatedAt = (Get-Date).ToString('o')
    cliPath     = $cliPath
    command     = $cliCommand
    args        = $cliArgsRecorded
    exitCode    = $cliExit
    diff        = $cliDiff
    cwd         = $repoRoot
    duration_s  = $cliDurationSeconds
    duration_ns = $cliDurationNanoseconds
    base        = $capture.base
    head        = $capture.head
  }
  $execObject | ConvertTo-Json -Depth 6 | Out-File -FilePath $execPath -Encoding utf8
}
else {
  $argsString = if ($flagTokens.Count -gt 0) { ($flagTokens -join ' ') } else { '' }
  $result = Invoke-CompareVI -Base $base -Head $head -LvComparePath $lvComparePathResolved -LvCompareArgs $argsString -CompareExecJsonPath $execPath -FailOnDiff:$false
  $cliExit = [int]$result.ExitCode
  $cliDiff = [bool]$result.Diff
  $cliCommand = $result.Command
  $cliPath = $result.CliPath
  $cliDurationSeconds = $result.CompareDurationSeconds
  $cliDurationNanoseconds = $result.CompareDurationNanoseconds
  if ($flagTokens.Count -gt 0) { $cliArgsRecorded = $flagTokens }
}

if (-not $cliDiff -and $cliExit -eq $null) { $cliExit = 0 }

$exec = Get-Content -LiteralPath $execPath -Raw | ConvertFrom-Json -Depth 6

$outPaths = [ordered]@{ execJson = (Resolve-Path -LiteralPath $execPath).Path }
foreach ($k in @('captureJson','stdout','stderr','reportHtml','imagesDir')) {
  if ($detailPaths.Contains($k) -and $detailPaths[$k]) { $outPaths[$k] = $detailPaths[$k] }
}
if ($artifactDir) { $outPaths.artifactDir = (Resolve-Path -LiteralPath $artifactDir).Path }

$cliSummary = [ordered]@{
  exitCode    = $cliExit
  diff        = [bool]$cliDiff
  duration_s  = $cliDurationSeconds
  command     = $cliCommand
  cliPath     = $cliPath
}
if ($cliDurationNanoseconds -ne $null) { $cliSummary.duration_ns = $cliDurationNanoseconds }
if ($cliArgsRecorded.Count -gt 0) { $cliSummary.args = $cliArgsRecorded }
if ($cliHighlights.Count -gt 0) { $cliSummary.highlights = $cliHighlights }
if ($cliStdoutPreview.Count -gt 0) { $cliSummary.stdoutPreview = $cliStdoutPreview }
if ($cliArtifacts) { $cliSummary.artifacts = $cliArtifacts }

$sum = [ordered]@{
  schema = 'ref-compare-summary/v1'
  generatedAt = (Get-Date).ToString('o')
  path = $Path
  refA = $RefA
  refB = $RefB
  temp = $tmp
  out = [pscustomobject]$outPaths
  computed = [ordered]@{
    baseBytes = $bytesBase
    headBytes = $bytesHead
    baseSha   = $shaBase
    headSha   = $shaHead
    expectDiff= $expectDiff
  }
  cli = [pscustomobject]$cliSummary
}
$sum | ConvertTo-Json -Depth 8 | Out-File -FilePath $sumPath -Encoding utf8

if (-not $Quiet) {
  Write-Host "Ref compare complete: $Path ($RefA vs $RefB)"
  Write-Host "- Exec: $execPath"
  Write-Host "- Summary: $sumPath"
  if ($artifactDir) { Write-Host "- Artifacts: $artifactDir" }
  Write-Host ("- ExpectDiff={0} | cli.diff={1} | exitCode={2}" -f $expectDiff,([bool]$cliDiff),$cliExit)
}

if ($FailOnDiff -and $cliDiff) {
  throw "LVCompare reported differences between refs: $RefA vs $RefB"
}

exit 0
