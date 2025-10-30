. (Join-Path $PSScriptRoot 'ReportFixtureHelpers.ps1')
$reportFixtureCases = Get-ReportFixtureCases

Describe 'Compare-VIHistory helper' -Tag 'Integration' {
  BeforeAll {
    $ErrorActionPreference = 'Stop'
    try { git --version | Out-Null } catch { throw 'git is required for this test' }

    $repoRoot = (Get-Location).Path
    $target = 'VI1.vi'
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $target))) {
      Set-ItResult -Skipped -Because "Target file not found: $target"
    }

    $revList = & git rev-list --max-count=12 HEAD -- $target
    if (-not $revList) { Set-ItResult -Skipped -Because 'No commit history for target'; return }

    $pairs = @()
    foreach ($head in $revList) {
      $parent = (& git rev-parse "$head^" 2>$null)
      if (-not $parent) { continue }
      $parent = ($parent -split "`n")[0].Trim()
      if (-not $parent) { continue }
      $pairs += [pscustomobject]@{
        Head = $head.Trim()
        Base = $parent
      }
    }
    if (-not $pairs) { Set-ItResult -Skipped -Because 'No parent commit pairs available'; return }

    $stubPath = Join-Path $TestDrive 'Invoke-LVCompare.stub.ps1'
    $stubContent = @'
param(
  [Parameter(Mandatory=$true)][string]$BaseVi,
  [Parameter(Mandatory=$true)][string]$HeadVi,
  [string]$OutputDir,
  [string]$LabVIEWExePath,
  [string]$LabVIEWBitness = '64',
  [string]$LVComparePath,
  [string[]]$Flags,
  [switch]$ReplaceFlags,
  [switch]$AllowSameLeaf,
  [switch]$RenderReport,
  [ValidateSet('html','xml','text')][string[]]$ReportFormat = 'html',
  [string]$JsonLogPath,
  [switch]$Quiet,
  [switch]$LeakCheck,
  [double]$LeakGraceSeconds = 0,
  [string]$LeakJsonPath,
  [string]$CaptureScriptPath,
  [switch]$Summary,
  [Nullable[int]]$TimeoutSeconds,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $OutputDir) {
  $OutputDir = Join-Path $env:TEMP ("history-stub-" + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$stdoutPath = Join-Path $OutputDir 'lvcompare-stdout.txt'
$stderrPath = Join-Path $OutputDir 'lvcompare-stderr.txt'
$exitPath   = Join-Path $OutputDir 'lvcompare-exitcode.txt'
$capturePath= Join-Path $OutputDir 'lvcompare-capture.json'
$leakPath   = if ($LeakJsonPath) { $LeakJsonPath } elseif ($LeakCheck) { Join-Path $OutputDir 'lvcompare-leak.json' } else { $null }
$imagesDir  = Join-Path $OutputDir 'cli-images'

if ($leakPath) {
  $leakDir = Split-Path -Parent $leakPath
  if ($leakDir) { New-Item -ItemType Directory -Path $leakDir -Force | Out-Null }
}
if ($JsonLogPath) {
  $logDir = Split-Path -Parent $JsonLogPath
  if ($logDir) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
}

$flagsArray = @()
if ($Flags) { $flagsArray = @($Flags | ForEach-Object { [string]$_ }) }
$reportToken = $null
$repFormatToken = $null
for ($i = 0; $i -lt $flagsArray.Count; $i++) {
  $token = $flagsArray[$i]
  if (-not $token) { continue }
  if ($token -ieq '-report' -and ($i + 1) -lt $flagsArray.Count) {
    $reportToken = $flagsArray[$i + 1]
  }
  if ($token -ieq '-repformat' -and ($i + 1) -lt $flagsArray.Count) {
    $repFormatToken = ([string]$flagsArray[$i + 1]).ToLowerInvariant()
  }
}
$renderReportSwitch = $PSBoundParameters.ContainsKey('RenderReport')
$reportFormatParam = 'html'
if ($ReportFormat -and $ReportFormat.Count -gt 0) {
  $reportFormatParam = ([string]$ReportFormat[$ReportFormat.Count - 1]).ToLowerInvariant()
}
if (-not $PSBoundParameters.ContainsKey('ReportFormat')) {
  $envReportFormat = [System.Environment]::GetEnvironmentVariable('COMPAREVI_REPORT_FORMAT','Process')
  if ($envReportFormat) { $reportFormatParam = $envReportFormat.ToLowerInvariant() }
}
if (-not $repFormatToken) { $repFormatToken = $reportFormatParam }
if (-not $repFormatToken) { $repFormatToken = 'html' }
if (-not $reportToken) {
  $reportExt = switch ($repFormatToken) {
    'xml'  { 'xml' }
    'text' { 'txt' }
    default { 'html' }
  }
  $reportToken = Join-Path $OutputDir ("compare-report.{0}" -f $reportExt)
}
$reportPath = $reportToken

$diff = if ($env:STUB_COMPARE_DIFF -eq '1') { $true } else { $false }
$exitCode = if ($diff) { 1 } else { 0 }

$stdoutLines = @(
  "Compare stub (diff=$diff)",
  "Base=$BaseVi",
  "Head=$HeadVi"
)
$stdoutLines | Set-Content -LiteralPath $stdoutPath -Encoding utf8
'' | Set-Content -LiteralPath $stderrPath -Encoding utf8
$exitCode.ToString() | Set-Content -LiteralPath $exitPath -Encoding utf8

$fixtureOverride = [System.Environment]::GetEnvironmentVariable('STUB_COMPARE_REPORT_FIXTURE','Process')
$fixtureReportCopied = $false
$fixtureCaptureCopied = $false
if (-not [string]::IsNullOrWhiteSpace($fixtureOverride)) {
  $fixtureRoot = $fixtureOverride
  if (-not (Test-Path -LiteralPath $fixtureRoot -PathType Container)) {
    $candidate = Join-Path (Split-Path -Parent $PSScriptRoot) $fixtureOverride
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      $fixtureRoot = $candidate
    } else {
      $fixtureRoot = $null
    }
  }
  if ($fixtureRoot) {
    $reportSource = Join-Path $fixtureRoot 'compare-report.html'
    $captureSource = Join-Path $fixtureRoot 'lvcompare-capture.json'
    $reportDir = [System.IO.Path]::GetDirectoryName($reportPath)
    if ($reportDir) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    if (Test-Path -LiteralPath $reportSource -PathType Leaf) {
      Copy-Item -LiteralPath $reportSource -Destination $reportPath -Force
      $fixtureReportCopied = $true
    }
    if (Test-Path -LiteralPath $captureSource -PathType Leaf) {
      Copy-Item -LiteralPath $captureSource -Destination $capturePath -Force
      $fixtureCaptureCopied = $true
    }
  }
}

if ((-not $fixtureReportCopied) -and ($renderReportSwitch -or $reportToken -or ($repFormatToken -ne 'html'))) {
  switch ($repFormatToken) {
    'xml'  { "<report diff='$diff' />" | Set-Content -LiteralPath $reportPath -Encoding utf8 }
    'text' { "Stub report diff=$diff" | Set-Content -LiteralPath $reportPath -Encoding utf8 }
    default { "<html><body><h1>Stub Report (diff=$diff)</h1></body></html>" | Set-Content -LiteralPath $reportPath -Encoding utf8 }
  }
}
New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $imagesDir 'cli-image-00.png'), @(0xCA,0xFE,0xBA,0xBE))

$metadata = [ordered]@{
  renderReport = $renderReportSwitch
  reportFlag   = $reportToken
  repFormat    = $repFormatToken
  paramFormat  = $reportFormatParam
  effectiveFormat = $repFormatToken
  reportPath   = $reportPath
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'report-flags.json') -Encoding utf8

if (-not $fixtureCaptureCopied) {
  $capture = [ordered]@{
    schema          = 'lvcompare-capture-v1'
    timestamp       = (Get-Date).ToString('o')
    base            = $BaseVi
    head            = $HeadVi
    cliPath         = if ($LVComparePath) { $LVComparePath } else { 'C:\Stub\LVCompare.exe' }
    args            = $Flags
    exitCode        = $exitCode
    seconds         = 0.05
    stdoutLen       = $stdoutLines.Count
    stderrLen       = 0
    command         = ("Stub LVCompare ""{0}"" ""{1}""" -f $BaseVi,$HeadVi)
    allowSameLeaf   = [bool]$AllowSameLeaf
    leakCheck       = [bool]$LeakCheck
    leakGrace       = $LeakGraceSeconds
    timeoutSeconds  = if ($TimeoutSeconds) { [int]$TimeoutSeconds } else { $null }
    labviewExePath  = $LabVIEWExePath
    labviewBitness  = $LabVIEWBitness
  }
  $capture | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $capturePath -Encoding utf8
}

$artifactLeaf = $null
$artifactParent = $null
if ($OutputDir) {
  try { $artifactLeaf = Split-Path -Leaf $OutputDir } catch { $artifactLeaf = $null }
  try { $artifactParent = Split-Path -Parent $OutputDir } catch { $artifactParent = $null }
}
if (-not $artifactLeaf) { $artifactLeaf = 'lvcompare-artifacts' }
$artifactBase = if ($artifactLeaf -and $artifactLeaf.EndsWith('-artifacts')) {
  $artifactLeaf.Substring(0, $artifactLeaf.Length - 10)
} else {
  $artifactLeaf
}
if (-not $artifactBase) { $artifactBase = 'lvcompare' }
$execPath = if ($artifactParent) {
  Join-Path $artifactParent ("$artifactBase-exec.json")
} else {
  Join-Path $OutputDir ("$artifactBase-exec.json")
}
$summaryPath = if ($artifactParent) {
  Join-Path $artifactParent ("$artifactBase-summary.json")
} else {
  Join-Path $OutputDir ("$artifactBase-summary.json")
}

$reportHighlights = @()
$includedAttributes = @()
if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
  $reportHtml = Get-Content -LiteralPath $reportPath -Raw
  $summaryMatches = [regex]::Matches($reportHtml, '<summary[^>]*>(?<text>[^<]+)</summary>', 'IgnoreCase')
  foreach ($match in $summaryMatches) {
    $text = $match.Groups['text'].Value.Trim()
    if ($text) { $reportHighlights += $text }
  }
  $attrMatches = [regex]::Matches($reportHtml, '<li\s+class="checked">(?<text>[^<]+)</li>', 'IgnoreCase')
  foreach ($match in $attrMatches) {
    $name = [System.Net.WebUtility]::HtmlDecode($match.Groups['text'].Value.Trim())
    if ($name) {
      $includedAttributes += ,([pscustomobject]@{
        name     = $name
        included = $true
      })
    }
  }
}
if ($includedAttributes.Count -gt 0) {
  foreach ($attr in $includedAttributes) {
    if ($attr -and $attr.name) { $reportHighlights += [string]$attr.name }
  }
  $attrNames = @($includedAttributes | ForEach-Object { $_.name } | Where-Object { $_ } | Select-Object -Unique)
  if ($attrNames.Count -gt 0) {
    $reportHighlights += ("Attributes: {0}" -f ([string]::Join(', ', $attrNames)))
  }
}
$uniqueHighlights = @($reportHighlights | Where-Object { $_ } | Select-Object -Unique)
$cliArgsRecorded = if ($Flags) { @($Flags | ForEach-Object { [string]$_ }) } else { $null }
$cliPathValue = if ($LVComparePath) { $LVComparePath } else { 'C:\Stub\LVCompare.exe' }
$cliCommandValue = ("Stub LVCompare ""{0}"" ""{1}""" -f $BaseVi,$HeadVi)

$execObject = [ordered]@{
  schema      = 'compare-exec/v1'
  generatedAt = (Get-Date).ToString('o')
  cliPath     = $cliPathValue
  command     = $cliCommandValue
  args        = $cliArgsRecorded
  exitCode    = $exitCode
  diff        = $diff
  cwd         = (Get-Location).Path
  duration_s  = 0.05
  duration_ns = 50000000
  base        = $BaseVi
  head        = $HeadVi
}
$execObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $execPath -Encoding utf8

$cliSummary = [ordered]@{
  exitCode     = $exitCode
  diff         = $diff
  duration_s   = 0.05
  command      = $cliCommandValue
  cliPath      = $cliPathValue
  reportFormat = $repFormatToken
}
if ($cliArgsRecorded) { $cliSummary.args = $cliArgsRecorded }
if ($uniqueHighlights.Count -gt 0) { $cliSummary.highlights = $uniqueHighlights }
if ($includedAttributes.Count -gt 0) { $cliSummary.includedAttributes = $includedAttributes }
if ($stdoutLines) { $cliSummary.stdoutPreview = $stdoutLines }

$outPaths = [ordered]@{
  execJson    = $execPath
  captureJson = $capturePath
  reportPath  = $reportPath
  stdout      = $stdoutPath
  stderr      = $stderrPath
}
if ($reportPath -and ($repFormatToken -eq 'html')) {
  $outPaths.reportHtml = $reportPath
}
$summaryObject = [ordered]@{
  schema      = 'ref-compare-summary/v1'
  generatedAt = (Get-Date).ToString('o')
  name        = Split-Path -Leaf $BaseVi
  path        = $BaseVi
  refA        = 'stub-refA'
  refB        = 'stub-refB'
  temp        = $OutputDir
  reportFormat = $repFormatToken
  out         = [pscustomobject]$outPaths
  computed    = [ordered]@{
    baseBytes  = 123
    headBytes  = 456
    baseSha    = 'stub-base'
    headSha    = 'stub-head'
    expectDiff = $diff
  }
  cli         = [pscustomobject]$cliSummary
}
$summaryObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8

if ($LeakCheck -and $leakPath) {
  $leakInfo = [ordered]@{
    schema       = 'lvcompare-leak-v1'
    generatedAt  = (Get-Date).ToString('o')
    leakDetected = $false
    processes    = @()
    graceSeconds = $LeakGraceSeconds
  }
  $leakInfo | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $leakPath -Encoding utf8
}

if ($JsonLogPath) {
  $crumb = [ordered]@{
    schema    = 'lvcompare-log-v1'
    event     = 'stub-run'
    timestamp = (Get-Date).ToString('o')
    diff      = $diff
    leakCheck = [bool]$LeakCheck
    base      = $BaseVi
    head      = $HeadVi
  }
  $crumb | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $JsonLogPath -Encoding utf8
}

if ($Summary) {
  Write-Host ("[Stub] LVCompare diff={0}" -f $diff)
}
exit 0
'@
    Set-Content -LiteralPath $stubPath -Value $stubContent -Encoding Unicode
    $script:CompareHistoryStubContent = $stubContent
    $script:CompareHistoryStubPath = $stubPath

    Set-Variable -Name '_repoRoot' -Value $repoRoot -Scope Script
    Set-Variable -Name '_pairs' -Value $pairs -Scope Script
    Set-Variable -Name '_target' -Value $target -Scope Script
    Set-Variable -Name '_stubPath' -Value $stubPath -Scope Script

    $firstParent = & git rev-list --first-parent HEAD
    $commits = @($firstParent | Where-Object { $_ })
    $touchMap = @{}
    foreach ($commit in $commits) {
      $changed = & git diff-tree --no-commit-id --name-only -r $commit -- $target
      $touchMap[$commit] = -not [string]::IsNullOrWhiteSpace($changed)
    }

    $candidateUp = $null
    $recentChange = $null
    foreach ($commit in $commits) {
      if ($touchMap[$commit]) {
        if (-not $recentChange) { $recentChange = $commit }
      } elseif ($recentChange) {
        $candidateUp = [pscustomobject]@{
          start    = $commit
          expected = $recentChange
        }
        break
      }
    }

    $candidateDown = $null
    $firstChange = $null
    foreach ($commit in $commits) {
      if ($touchMap[$commit]) { $firstChange = $commit; break }
    }
    if ($firstChange) {
      foreach ($commit in $commits) {
        if ($commit -eq $firstChange) { break }
        if (-not $touchMap[$commit]) {
          $candidateDown = [pscustomobject]@{
            start    = $commit
            expected = $firstChange
          }
          break
        }
      }
    }

    Set-Variable -Name '_shiftUpCandidate' -Value $candidateUp -Scope Script
    Set-Variable -Name '_shiftDownCandidate' -Value $candidateDown -Scope Script
  }

  AfterAll {
    Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
  }

  $getHistoryManifests = {
    param(
      [Parameter(Mandatory = $true)][string]$RootDir,
      [string]$ModeSlug = 'default'
    )

    $suitePath = Join-Path $RootDir 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $suiteManifest = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $suiteManifest.schema | Should -Be 'vi-compare/history-suite@v1'

    $modeEntry = $suiteManifest.modes | Where-Object { $_.slug -eq $ModeSlug }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue

    $modeManifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    return [pscustomobject]@{
      SuitePath     = $suitePath
      SuiteManifest = $suiteManifest
      ModeEntry     = $modeEntry
      ModeManifest  = $modeManifest
    }
  }

  It 'produces manifest without artifacts when no diffs detected' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-no-diff'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -FailOnDiff:$false `
      -Mode default `
      -ReportFormat html | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'default' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json

    $aggregate.stats.processed | Should -Be 1
    $aggregate.stats.diffs | Should -Be 0
    $aggregate.stats.missing | Should -Be 0
    $manifest.schema | Should -Be 'vi-compare/history@v1'
    $manifest.reportFormat | Should -Be 'html'
    $manifest.flags | Should -Contain '-nobd'
    $manifest.flags | Should -Contain '-noattr'
    $manifest.flags | Should -Contain '-nofp'
    $manifest.flags | Should -Contain '-nofppos'
    $manifest.flags | Should -Contain '-nobdcosm'
    $manifest.stats.processed | Should -Be 1
    $manifest.stats.diffs | Should -Be 0
    $manifest.stats.stopReason | Should -Be 'max-pairs'
    $manifest.comparisons.Count | Should -Be 1
    $manifest.comparisons[0].reportFormat | Should -Be 'html'
    $manifest.comparisons[0].result.diff | Should -BeFalse
    ($manifest.comparisons[0].result.PSObject.Properties['artifactDir']) | Should -Be $null
  }

  It 'retains artifact directory when the stub reports a diff' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '1'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-diff'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Detailed `
      -RenderReport `
      -FailOnDiff:$false `
      -Mode default | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'default' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.stats.diffs | Should -Be 1
    $manifest.flags | Should -Contain '-nobd'
    $manifest.flags | Should -Contain '-noattr'
    $manifest.flags | Should -Contain '-nofp'
    $manifest.flags | Should -Contain '-nofppos'
    $manifest.flags | Should -Contain '-nobdcosm'
    $manifest.stats.lastDiffIndex | Should -Be 1
    $manifest.comparisons[0].result.diff | Should -BeTrue
    $artifactDir = $manifest.comparisons[0].result.artifactDir
    [string]::IsNullOrWhiteSpace($artifactDir) | Should -BeFalse
    Test-Path -LiteralPath $artifactDir | Should -BeTrue
  }

  It 'captures xml report when alternate format requested' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '1'
    try {
      $pair = $_pairs[0]
      $rd = Join-Path $TestDrive 'history-xml'
      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $rd `
      -Detailed `
      -ReportFormat xml `
      -FailOnDiff:$false | Out-Null

      $suitePath = Join-Path $rd 'manifest.json'
      Test-Path -LiteralPath $suitePath | Should -BeTrue
      $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
      $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'default' }
      $modeEntry | Should -Not -BeNullOrEmpty
      Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
      $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
      $comparison = $manifest.comparisons[0]
      $comparison.reportFormat | Should -Be 'xml'
      $comparison.result.diff | Should -BeTrue
      $comparison.result.PSObject.Properties['reportHtml'] | Should -Be $null
      $artifactDir = $comparison.result.artifactDir
      [string]::IsNullOrWhiteSpace($artifactDir) | Should -BeFalse
      Test-Path -LiteralPath $artifactDir | Should -BeTrue
      Test-Path -LiteralPath (Join-Path $artifactDir 'compare-report.xml') | Should -BeTrue

      $metaPath = Join-Path $artifactDir 'report-flags.json'
      Test-Path -LiteralPath $metaPath | Should -BeTrue
      $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
      $meta.effectiveFormat | Should -Be 'xml'
      $meta.reportPath | Should -Match '\.xml$'
    }
    finally {
      $env:STUB_COMPARE_DIFF = '0'
    }
  }

  It 'shifts start ref to the next change when a more recent commit modified the VI' {
    if (-not $_shiftUpCandidate) { Set-ItResult -Skipped -Because 'No suitable ancestor commit without change found'; return }
    $candidate = $_shiftUpCandidate
    $rd = Join-Path $TestDrive 'history-shift-up'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $candidate.start `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Detailed `
      -RenderReport `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'default' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.requestedStartRef | Should -Be $candidate.start
    $manifest.startRef | Should -Be $candidate.expected
    $manifest.comparisons.Count | Should -Be 1
    $manifest.comparisons[0].head.ref | Should -Be $candidate.expected
  }

  It 'falls back to the previous change when no newer commits touched the VI' {
    if (-not $_shiftDownCandidate) { Set-ItResult -Skipped -Because 'No suitable descendant commit without change found'; return }
    $candidate = $_shiftDownCandidate
    $rd = Join-Path $TestDrive 'history-shift-down'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $candidate.start `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Detailed `
      -RenderReport `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'default' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.requestedStartRef | Should -Be $candidate.start
    $manifest.startRef | Should -Be $candidate.expected
    $manifest.comparisons.Count | Should -BeGreaterThan 0
    $manifest.comparisons[0].head.ref | Should -Be $candidate.expected
  }

  It 'exposes attribute-focused mode when requested' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-attributes'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Detailed `
      -RenderReport `
      -FailOnDiff:$false `
      -Mode attributes | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'attributes' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.mode | Should -Be 'attributes'
    ($manifest.flags -contains '-noattr') | Should -BeFalse
    $manifest.flags | Should -Contain '-nobd'
    $manifest.flags | Should -Contain '-nofp'
    $manifest.flags | Should -Contain '-nofppos'
    $manifest.flags | Should -Contain '-nobdcosm'
    $manifest.comparisons.Count | Should -Be 1
    $manifest.comparisons[0].mode | Should -Be 'attributes'
  }

  It 'drops front panel ignores when front-panel mode is selected' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-frontpanel'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'front-panel' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'front-panel' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.mode | Should -Be 'front-panel'
    ($manifest.flags -contains '-nofp') | Should -BeFalse
    ($manifest.flags -contains '-nofppos') | Should -BeFalse
    $manifest.flags | Should -Contain '-nobd'
    $manifest.flags | Should -Contain '-noattr'
    $manifest.flags | Should -Contain '-nobdcosm'
  }

  It 'drops block diagram cosmetic ignore when block-diagram mode is selected' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-blockdiagram'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'block-diagram' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'block-diagram' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.mode | Should -Be 'block-diagram'
    ($manifest.flags -contains '-nobdcosm') | Should -BeFalse
    $manifest.flags | Should -Contain '-nobd'
    $manifest.flags | Should -Contain '-noattr'
    $manifest.flags | Should -Contain '-nofp'
    $manifest.flags | Should -Contain '-nofppos'
  }

  It 'removes all ignore flags when mode is "all"' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-all-diffs'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'all' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'all' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.mode | Should -Be 'all'
    $manifest.flags | Should -BeNullOrEmpty
  }

  It 'removes all ignore flags when mode is "full"' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-full-diffs'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'full' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $aggregate = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $modeEntry = $aggregate.modes | Where-Object { $_.slug -eq 'full' }
    $modeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $modeEntry.manifestPath | Should -BeTrue
    $manifest = Get-Content -LiteralPath $modeEntry.manifestPath -Raw | ConvertFrom-Json
    $manifest.mode | Should -Be 'full'
    $manifest.flags | Should -BeNullOrEmpty
  }

  It 'executes multiple modes and writes per-mode manifests' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-multi-mode'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'default,attributes' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $suiteManifest = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $suiteManifest.modes.Count | Should -Be 2
    $defaultEntry = $suiteManifest.modes | Where-Object { $_.slug -eq 'default' }
    $attributeEntry = $suiteManifest.modes | Where-Object { $_.slug -eq 'attributes' }
    $defaultEntry | Should -Not -BeNullOrEmpty
    $attributeEntry | Should -Not -BeNullOrEmpty
    Test-Path -LiteralPath $defaultEntry.manifestPath | Should -BeTrue
    Test-Path -LiteralPath $attributeEntry.manifestPath | Should -BeTrue

    $defaultManifest = Get-Content -LiteralPath $defaultEntry.manifestPath -Raw | ConvertFrom-Json
    $defaultManifest.mode | Should -Be 'default'
    $attributeManifest = Get-Content -LiteralPath $attributeEntry.manifestPath -Raw | ConvertFrom-Json
    $attributeManifest.mode | Should -Be 'attributes'
  }

  It 'emits GitHub outputs describing aggregate and per-mode manifests' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-github-output'
    $outputPath = Join-Path $TestDrive 'github-output.txt'
    $summaryPath = Join-Path $TestDrive 'github-summary.md'

    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'default,attributes' `
      -GitHubOutputPath $outputPath `
      -StepSummaryPath $summaryPath `
      -FailOnDiff:$false | Out-Null

    Test-Path -LiteralPath $outputPath | Should -BeTrue
    $outputLines = Get-Content -LiteralPath $outputPath

    $manifestLine = $outputLines | Where-Object { $_ -like 'manifest-path=*' } | Select-Object -First 1
    $manifestLine | Should -Not -BeNullOrEmpty
    $manifestValue = (($manifestLine -split '=', 2)[1]).Trim()
    $manifestValue | Should -Match 'manifest\.json$'
    Test-Path -LiteralPath $manifestValue | Should -BeTrue

    $modeJsonLine = $outputLines | Where-Object { $_ -like 'mode-manifests-json=*' } | Select-Object -First 1
    $modeJsonLine | Should -Not -BeNullOrEmpty
    $modeJsonValue = (($modeJsonLine -split '=', 2)[1]).Trim()
    $modeSummary = $modeJsonValue | ConvertFrom-Json
    $modeSummary.Count | Should -Be 2

    $bySlug = @{}
    foreach ($entry in $modeSummary) {
      $entry | Should -Not -BeNullOrEmpty
      $entry.mode | Should -Not -BeNullOrEmpty
      $entry.manifest | Should -Not -BeNullOrEmpty
      Test-Path -LiteralPath $entry.manifest | Should -BeTrue
      $entry.resultsDir | Should -Not -BeNullOrEmpty
      $bySlug[$entry.slug] = $entry
    }

    $bySlug.ContainsKey('default') | Should -BeTrue
    $bySlug.ContainsKey('attributes') | Should -BeTrue
    $bySlug['default'].mode | Should -Be 'default'
    $bySlug['attributes'].mode | Should -Be 'attributes'

    $historyMdLine = $outputLines | Where-Object { $_ -like 'history-report-md=*' } | Select-Object -First 1
    $historyMdLine | Should -Not -BeNullOrEmpty
    $historyMdPath = (($historyMdLine -split '=', 2)[1]).Trim()
    Test-Path -LiteralPath $historyMdPath | Should -BeTrue

    $historyHtmlLine = $outputLines | Where-Object { $_ -like 'history-report-html=*' } | Select-Object -First 1
    $historyHtmlLine | Should -Not -BeNullOrEmpty
    $historyHtmlPath = (($historyHtmlLine -split '=', 2)[1]).Trim()
    Test-Path -LiteralPath $historyHtmlPath | Should -BeTrue

    Test-Path -LiteralPath $summaryPath | Should -BeTrue
    $summaryContent = Get-Content -LiteralPath $summaryPath -Raw
    $summaryContent | Should -Match 'VI history report'
    $summaryContent | Should -Match 'history-report.md'
  }

  It 'renders enriched history report with commit metadata and artifact links' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $previousDiff = $env:STUB_COMPARE_DIFF
    try {
      $env:STUB_COMPARE_DIFF = '1'
      $pair = $_pairs[0]
      $rd = Join-Path $TestDrive 'history-report-rich'

      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $rd `
        -Mode 'default' `
        -FailOnDiff:$false | Out-Null

      $historyMd = Get-Content -LiteralPath (Join-Path $rd 'history-report.md') -Raw
      $historyMd | Should -Match '\#\# Commit pairs'
      $historyMd | Should -Match '\| Mode \| Pair \| Base \| Head \| Diff \| Duration \(s\) \| Categories \| Report \| Highlights \|'
      $historyMd | Should -Match '\*\*diff\*\*'
      $historyMd | Should -Match '\[report\]\(\./'
      $historyMd | Should -Match '<sub>.* - .*<\/sub>'
      $historyMd | Should -Match '\#\# Attribute coverage'

      $historyHtml = Get-Content -LiteralPath (Join-Path $rd 'history-report.html') -Raw
      $historyHtml | Should -Match '<h2>Attribute coverage</h2>'
      $historyHtml | Should -Match '<th>Categories</th>'
      $historyHtml | Should -Match '<td class="diff-yes">Diff</td>'
    } finally {
      if ($null -eq $previousDiff) {
        Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
      } else {
        $env:STUB_COMPARE_DIFF = $previousDiff
      }
    }
  }

  Describe 'Attribute coverage flag scaffolding' {
    $fixtureCases = @(
      @{
        Name          = 'BlockDiagramFunctional'
        Param         = 'ForceNoBd'
        FixtureRel    = Join-Path 'fixtures' 'vi-report' 'block-diagram'
        ExpectPattern = 'Block Diagram'
        ExpectedCategories = @('block-diagram')
      }
      @{
        Name          = 'VIAttribute'
        Param         = 'FlagNoAttr'
        FixtureRel    = Join-Path 'fixtures' 'vi-report' 'vi-attribute'
        ExpectPattern = 'VI Attribute'
        ExpectedCategories = @('attributes')
      }
      @{
        Name          = 'FrontPanel'
        Param         = 'FlagNoFp'
        FixtureRel    = Join-Path 'fixtures' 'vi-report' 'front-panel'
        ExpectPattern = 'Front Panel'
        ExpectedCategories = @('front-panel')
      }
      @{
        Name          = 'FrontPanelPosition'
        Param         = 'FlagNoFpPos'
        FixtureRel    = Join-Path 'fixtures' 'vi-report' 'front-panel'
        ExpectPattern = 'Front Panel Position/Size'
        ExpectedCategories = @('front-panel')
      }
      @{
        Name          = 'BlockDiagramCosmetic'
        Param         = 'FlagNoBdCosm'
        FixtureRel    = Join-Path 'fixtures' 'vi-report' 'block-diagram'
        ExpectPattern = 'Block Diagram Cosmetic'
        ExpectedCategories = @('cosmetic')
      }
    )

    It "surfaces highlights when <Param> suppression is removed (<Name>)" -TestCases $fixtureCases {
      param($Name, $Param, $FixtureRel, $ExpectPattern, $ExpectedCategories)
      if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }

      $pair = $_pairs[0]
      $compareScript = Join-Path $_repoRoot 'tools' 'Compare-VIHistory.ps1'
      $baselineDir = Join-Path $TestDrive ("history-flag-{0}-baseline" -f $Name)
      $variantDir  = Join-Path $TestDrive ("history-flag-{0}-variant" -f $Name)
      $fixturePath = Join-Path $_repoRoot $FixtureRel

      $env:STUB_COMPARE_DIFF = '1'
      Remove-Item Env:STUB_COMPARE_REPORT_FIXTURE -ErrorAction SilentlyContinue

      try {
        $baselineParams = @{
          TargetPath       = $_target
          StartRef         = $pair.Head
          MaxPairs         = 1
          InvokeScriptPath = $_stubPath
          ResultsDir       = $baselineDir
          FailOnDiff       = $false
          Mode             = 'default'
          ReportFormat     = 'html'
        }
        & $compareScript @baselineParams | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'Baseline history compare should succeed'

        $baselineManifestPath = Join-Path $baselineDir 'default' 'manifest.json'
        Test-Path -LiteralPath $baselineManifestPath | Should -BeTrue -Because 'Baseline manifest should exist'
        $baselineManifest = Get-Content -LiteralPath $baselineManifestPath -Raw | ConvertFrom-Json
        $baselineHighlights = @()
        if ($baselineManifest.comparisons -and $baselineManifest.comparisons.Count -gt 0) {
          $firstResult = $baselineManifest.comparisons[0].result
          if ($firstResult -and $firstResult.PSObject.Properties['highlights'] -and $firstResult.highlights) {
            $baselineHighlights += @($firstResult.highlights)
          }
        }
        $baselineHighlights.Count | Should -Be 0 -Because 'Highlights should be suppressed baseline'

        $env:STUB_COMPARE_REPORT_FIXTURE = $fixturePath

        $variantParams = @{
          TargetPath       = $_target
          StartRef         = $pair.Head
          MaxPairs         = 1
          InvokeScriptPath = $_stubPath
          ResultsDir       = $variantDir
          FailOnDiff       = $false
          Mode             = 'default'
          ReportFormat     = 'html'
        }
        $variantParams[$Param] = $false
        & $compareScript @variantParams | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'Variant history compare should succeed'

        $variantManifestPath = Join-Path $variantDir 'default' 'manifest.json'
        Test-Path -LiteralPath $variantManifestPath | Should -BeTrue -Because 'Variant manifest should exist'
        $variantManifest = Get-Content -LiteralPath $variantManifestPath -Raw | ConvertFrom-Json
        $variantHighlights = @()
        if ($variantManifest.comparisons -and $variantManifest.comparisons.Count -gt 0) {
          $variantResult = $variantManifest.comparisons[0].result
          if ($variantResult -and $variantResult.PSObject.Properties['highlights'] -and $variantResult.highlights) {
            $variantHighlights += @($variantResult.highlights)
          }
          $variantCategories = @()
          if ($variantResult -and $variantResult.PSObject.Properties['categories'] -and $variantResult.categories) {
            foreach ($categoryValue in @($variantResult.categories)) {
              if ($categoryValue -is [System.Collections.IEnumerable] -and -not ($categoryValue -is [string])) {
                foreach ($subCategory in $categoryValue) {
                  if ($null -ne $subCategory -and -not [string]::IsNullOrWhiteSpace($subCategory)) {
                    $variantCategories += [string]$subCategory
                  }
                }
              } elseif ($null -ne $categoryValue -and -not [string]::IsNullOrWhiteSpace($categoryValue)) {
                $variantCategories += [string]$categoryValue
              }
            }
          }
            if ($ExpectedCategories) {
            foreach ($expectedCategory in $ExpectedCategories) {
              if (-not ($variantCategories -contains $expectedCategory)) {
                throw "Expected category '$expectedCategory' not found in variant categories: $($variantCategories -join ', ')"
              }
            }
            if ($variantCategories) {
              if ($variantCategories.Count -lt $ExpectedCategories.Count) {
                throw "Expected at least $($ExpectedCategories.Count) categories but saw $($variantCategories.Count)"
              }
            }
          }
        }

        $variantHighlights.Count | Should -BeGreaterThan 0 -Because 'Highlights should appear when suppression removed'
        ($variantHighlights -join ' ') | Should -Match $ExpectPattern
      }
      finally {
        Remove-Item Env:STUB_COMPARE_REPORT_FIXTURE -ErrorAction SilentlyContinue
        Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
      }
    }
  }

  It 'summarizes diff metrics in report tables' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $originalDiff = $env:STUB_COMPARE_DIFF
    try {
      $pair = $_pairs[0]

      $env:STUB_COMPARE_DIFF = '1'
      $diffDir = Join-Path $TestDrive 'history-diff-metric'
      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $diffDir `
        -Mode 'default' `
        -FailOnDiff:$false | Out-Null

      $diffReport = Get-Content -LiteralPath (Join-Path $diffDir 'history-report.md') -Raw
      $diffReport | Should -Match '\| Mode \| Pair \| Base \| Head \| Diff \| Duration \(s\) \| Categories \| Report \| Highlights \|'
      $diffReport | Should -Match '\| Diffs \|\s*1\s*\|'
      $diffReport | Should -Match '\| default \|\s*1\s*\|'
      $diffReport | Should -Match '-nobd'

      $env:STUB_COMPARE_DIFF = '0'
      $cleanDir = Join-Path $TestDrive 'history-clean-metric'
      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $cleanDir `
        -Mode 'default' `
        -FailOnDiff:$false | Out-Null

      $cleanReport = Get-Content -LiteralPath (Join-Path $cleanDir 'history-report.md') -Raw
      $cleanReport | Should -Match '\| Mode \| Pair \| Base \| Head \| Diff \| Duration \(s\) \| Categories \| Report \| Highlights \|'
      $cleanReport | Should -Match '\| Diffs \|\s*0\s*\|'
      $cleanReport | Should -Match '-nobd'
    } finally {
      if ($null -eq $originalDiff) {
        Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
      } else {
        $env:STUB_COMPARE_DIFF = $originalDiff
      }
    }
  }

  It 'carries report fixture content for <Name>' -TestCases $reportFixtureCases {
    param($Name, $FixtureRoot, $Headings)
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }

    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive ("history-fixture-{0}" -f $Name)
    $originalDiff = $env:STUB_COMPARE_DIFF
    $originalFixture = $env:STUB_COMPARE_REPORT_FIXTURE
    try {
      $env:STUB_COMPARE_DIFF = '1'
      $env:STUB_COMPARE_REPORT_FIXTURE = $FixtureRoot

      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $rd `
        -Mode 'default' `
        -FailOnDiff:$false | Out-Null
      $LASTEXITCODE | Should -Be 0 -Because 'History compare should succeed'
    } finally {
      if ($null -eq $originalDiff) {
        Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
      } else {
        $env:STUB_COMPARE_DIFF = $originalDiff
      }

      if ($null -eq $originalFixture) {
        Remove-Item Env:STUB_COMPARE_REPORT_FIXTURE -ErrorAction SilentlyContinue
      } else {
        $env:STUB_COMPARE_REPORT_FIXTURE = $originalFixture
      }
    }

    $reportFiles = @(Get-ChildItem -LiteralPath $rd -Filter 'compare-report.html' -File -Recurse)
    ($reportFiles.Count) | Should -BeGreaterThan 0

    $primaryReport = $reportFiles[0].FullName
    Test-Path -LiteralPath $primaryReport | Should -BeTrue
    $reportHtml = Get-Content -LiteralPath $primaryReport -Raw
    foreach ($heading in $Headings) {
      $reportHtml | Should -Match ([regex]::Escape($heading))
    }

    $historyMarkdownPath = Join-Path $rd 'history-report.md'
    Test-Path -LiteralPath $historyMarkdownPath | Should -BeTrue -Because 'History markdown should exist'
    $historyMd = Get-Content -LiteralPath $historyMarkdownPath -Raw
    $historyMd | Should -Match 'compare-report\.html'
  }

  It 'records commit pair modes in history tables' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $originalDiff = $env:STUB_COMPARE_DIFF
    try {
      $env:STUB_COMPARE_DIFF = '1'
      $pair = $_pairs[0]
      $rd = Join-Path $TestDrive 'history-multi-mode-table'
      & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
        -TargetPath $_target `
        -StartRef $pair.Head `
        -MaxPairs 1 `
        -InvokeScriptPath $_stubPath `
        -ResultsDir $rd `
        -Mode 'default,attributes' `
        -FailOnDiff:$false | Out-Null

      $historyMd = Get-Content -LiteralPath (Join-Path $rd 'history-report.md') -Raw
      $historyMd | Should -Match '\| Mode \| Pair \| Base \| Head \| Diff \| Duration \(s\) \| Categories \| Report \| Highlights \|'
      $historyMd | Should -Match '\| default \|\s*1\s*\|'
      $historyMd | Should -Match '\| attributes \|\s*1\s*\|'
    } finally {
      if ($null -eq $originalDiff) {
        Remove-Item Env:STUB_COMPARE_DIFF -ErrorAction SilentlyContinue
      } else {
        $env:STUB_COMPARE_DIFF = $originalDiff
      }
    }
  }

  It 'expands comma-separated mode tokens into multiple entries' {
    if (-not $_pairs) { Set-ItResult -Skipped -Because 'Missing commit data'; return }
    $env:STUB_COMPARE_DIFF = '0'
    $pair = $_pairs[0]
    $rd = Join-Path $TestDrive 'history-multi-token'
    & pwsh -NoLogo -NoProfile -File (Join-Path $_repoRoot 'tools/Compare-VIHistory.ps1') `
      -TargetPath $_target `
      -StartRef $pair.Head `
      -MaxPairs 1 `
      -InvokeScriptPath $_stubPath `
      -ResultsDir $rd `
      -Mode 'default,attributes' `
      -FailOnDiff:$false | Out-Null

    $suitePath = Join-Path $rd 'manifest.json'
    Test-Path -LiteralPath $suitePath | Should -BeTrue
    $suiteManifest = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $suiteManifest.modes.Count | Should -Be 2
    $slugs = @($suiteManifest.modes | ForEach-Object { $_.slug })
    $slugs | Should -Contain 'default'
    $slugs | Should -Contain 'attributes'
  }
}

Describe 'Compare-VIHistory source control handling' -Tag 'Integration' {
  BeforeAll {
    $script:RepoRoot = (Get-Location).Path
    $compareScript = Join-Path $script:RepoRoot 'tools' 'Compare-VIHistory.ps1'
    $localConfigPath = Join-Path $script:RepoRoot 'configs' 'labview-paths.local.json'
    $script:CompareScript = $compareScript
    $script:LocalConfigPath = $localConfigPath
    $script:OriginalLocalConfig = $null
    $script:HadLocalConfig = Test-Path -LiteralPath $localConfigPath -PathType Leaf
    if ($script:HadLocalConfig) {
      $script:OriginalLocalConfig = Get-Content -LiteralPath $localConfigPath -Raw
    }
    $script:SccStubPath = Join-Path $TestDrive 'Invoke-LVCompare.stub.ps1'
    if ($script:CompareHistoryStubContent) {
      Set-Content -LiteralPath $script:SccStubPath -Value $script:CompareHistoryStubContent -Encoding Unicode
    }
  }

  AfterEach {
    if (Test-Path -LiteralPath $script:LocalConfigPath -PathType Leaf) {
      Remove-Item -LiteralPath $script:LocalConfigPath -Force
    }
  }

  AfterAll {
    if ($script:HadLocalConfig) {
      Set-Content -LiteralPath $script:LocalConfigPath -Value $script:OriginalLocalConfig
    } else {
      if (Test-Path -LiteralPath $script:LocalConfigPath -PathType Leaf) {
        Remove-Item -LiteralPath $script:LocalConfigPath -Force
      }
    }
  }

  It 'detects when SCC is enabled in LabVIEW.ini' {
    $tempRoot = Join-Path $TestDrive 'lv-scc-enabled'
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $fakeExe = Join-Path $tempRoot 'LabVIEW.exe'
    [System.IO.File]::WriteAllBytes($fakeExe, [byte[]]@()) | Out-Null
    $fakeIni = Join-Path $tempRoot 'LabVIEW.ini'
    Set-Content -LiteralPath $fakeIni -Value "SCCUseInLabVIEW=True`nSCCProviderIsActive=True`n" -Encoding ascii

    @"
{
  "labview": [ "$fakeExe" ]
}
"@ | Set-Content -LiteralPath $script:LocalConfigPath
    Import-Module (Join-Path $script:RepoRoot 'tools' 'VendorTools.psm1') -Force
    $resolvedIni = Get-LabVIEWIniPath -LabVIEWExePath $fakeExe
    $resolvedIni | Should -Exist
    $iniUse = Get-LabVIEWIniValue -LabVIEWExePath $fakeExe -Key 'SCCUseInLabVIEW'
    $iniProvider = Get-LabVIEWIniValue -LabVIEWExePath $fakeExe -Key 'SCCProviderIsActive'
    $iniUse | Should -Be 'True'
    $iniProvider | Should -Be 'True'
  }

  It 'detects when SCC is disabled in LabVIEW.ini' {
    $tempRoot = Join-Path $TestDrive 'lv-scc-disabled'
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $fakeExe = Join-Path $tempRoot 'LabVIEW.exe'
    [System.IO.File]::WriteAllBytes($fakeExe, [byte[]]@()) | Out-Null
    $fakeIni = Join-Path $tempRoot 'LabVIEW.ini'
    Set-Content -LiteralPath $fakeIni -Value "SCCUseInLabVIEW=False`nSCCProviderIsActive=False`n" -Encoding ascii

    @"
{
  "labview": [ "$fakeExe" ]
}
"@ | Set-Content -LiteralPath $script:LocalConfigPath

    Import-Module (Join-Path $script:RepoRoot 'tools' 'VendorTools.psm1') -Force
    $resolvedIni = Get-LabVIEWIniPath -LabVIEWExePath $fakeExe
    $resolvedIni | Should -Exist
    $iniUse = Get-LabVIEWIniValue -LabVIEWExePath $fakeExe -Key 'SCCUseInLabVIEW'
    $iniProvider = Get-LabVIEWIniValue -LabVIEWExePath $fakeExe -Key 'SCCProviderIsActive'
    $iniUse | Should -Be 'False'
    $iniProvider | Should -Be 'False'
  }
}



