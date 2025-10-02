set-strictmode -version latest
$ErrorActionPreference = 'Stop'

function Resolve-Cli {
  param(
    [string]$Explicit
  )
  $canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'

  # If explicit path provided, enforce canonical path only
  if ($Explicit) {
    $resolved = try { (Resolve-Path -LiteralPath $Explicit -ErrorAction Stop).Path } catch { $Explicit }
    if ($resolved -ieq $canonical) {
      if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "LVCompare.exe not found at canonical path: $canonical"
      }
      return $canonical
    } else {
      throw "Only the canonical LVCompare path is supported: $canonical"
    }
  }

  # If environment variable provided, enforce canonical
  if ($env:LVCOMPARE_PATH) {
    $resolvedEnv = try { (Resolve-Path -LiteralPath $env:LVCOMPARE_PATH -ErrorAction Stop).Path } catch { $env:LVCOMPARE_PATH }
    if ($resolvedEnv -ieq $canonical) {
      if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
        throw "LVCompare.exe not found at canonical path: $canonical"
      }
      return $canonical
    } else {
      throw "Only the canonical LVCompare path is supported via LVCOMPARE_PATH: $canonical"
    }
  }

  # Default to canonical
  if (Test-Path -LiteralPath $canonical -PathType Leaf) {
    return $canonical
  }

  throw "LVCompare.exe not found. Install at: $canonical"
}

function Quote($s) {
  if ($null -eq $s) { return '""' }
  if ($s -match '\s|"') { return '"' + ($s -replace '"','\"') + '"' } else { return $s }
}

function Invoke-CompareVI {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Base,
    [Parameter(Mandatory)] [string] $Head,
    [string] $LvComparePath,
    [string] $LvCompareArgs = '',
    [string] $WorkingDirectory = '',
    [bool] $FailOnDiff = $true,
    [string] $GitHubOutputPath,
    [string] $GitHubStepSummaryPath,
    [ScriptBlock] $Executor
  )

  $pushed = $false
  if ($WorkingDirectory) {
    if (-not (Test-Path -LiteralPath $WorkingDirectory)) { throw "working-directory not found: $WorkingDirectory" }
    Push-Location -LiteralPath $WorkingDirectory
    $pushed = $true
  }
  try {
    if ([string]::IsNullOrWhiteSpace($Base)) { throw "Input 'base' is required and cannot be empty" }
    if ([string]::IsNullOrWhiteSpace($Head)) { throw "Input 'head' is required and cannot be empty" }
    if (-not (Test-Path -LiteralPath $Base)) { throw "Base VI not found: $Base" }
    if (-not (Test-Path -LiteralPath $Head)) { throw "Head VI not found: $Head" }

    $baseAbs = (Resolve-Path -LiteralPath $Base).Path
    $headAbs = (Resolve-Path -LiteralPath $Head).Path

    $cli = Resolve-Cli -Explicit $LvComparePath

    $cliArgs = @()
    if ($LvCompareArgs) {
      $pattern = '"[^"]+"|\S+'
      $tokens = [regex]::Matches($LvCompareArgs, $pattern) | ForEach-Object { $_.Value }
      foreach ($t in $tokens) { $cliArgs += $t.Trim('"') }
    }

    $cmdline = (@(Quote $cli; Quote $baseAbs; Quote $headAbs) + ($cliArgs | ForEach-Object { Quote $_ })) -join ' '

    # Measure execution time
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Execute via injected executor for tests, or call CLI directly
    $code = $null
    if ($Executor) {
      # Pass args as a single array to avoid unrolling
      $code = & $Executor $cli $baseAbs $headAbs ,$cliArgs
    }
    else {
      & $cli $baseAbs $headAbs @cliArgs
      # Capture exit code (use 0 as fallback if LASTEXITCODE not yet set in session)
      $code = if (Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue) { $LASTEXITCODE } else { 0 }
    }
  $sw.Stop()
  $compareDurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 3)
  # High resolution nanosecond precision (Stopwatch ticks * (1e9 / Frequency))
  $compareDurationNanoseconds = [long]([double]$sw.ElapsedTicks * (1e9 / [double][System.Diagnostics.Stopwatch]::Frequency))

    $cwd = (Get-Location).Path

    $diff = $false
    if ($code -eq 1) { $diff = $true }
    elseif ($code -eq 0) { $diff = $false }
    else {
      if ($GitHubOutputPath) {
        "exitCode=$code"   | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
        "cliPath=$cli"     | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
        "command=$cmdline" | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
        "diff=false"       | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      }
      if ($GitHubStepSummaryPath) {
        $summaryLines = @(
          '### Compare VI',
          "- Working directory: $cwd",
          "- Base: $baseAbs",
          "- Head: $headAbs",
          "- CLI: $cli",
          "- Command: $cmdline",
          "- Exit code: $code",
          "- Diff: false"
        )
        ($summaryLines -join "`n") | Out-File -FilePath $GitHubStepSummaryPath -Append -Encoding utf8
      }
      throw "Compare CLI failed with exit code $code"
    }

    if ($GitHubOutputPath) {
      "exitCode=$code"        | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      "cliPath=$cli"          | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      "command=$cmdline"      | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      $diffLower = if ($diff) { 'true' } else { 'false' }
      "diff=$diffLower"       | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
  "compareDurationSeconds=$compareDurationSeconds" | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
  "compareDurationNanoseconds=$compareDurationNanoseconds" | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
    }

    if ($GitHubStepSummaryPath) {
      $diffStr = if ($diff) { 'true' } else { 'false' }
      $summaryLines = @(
        '### Compare VI',
        "- Working directory: $cwd",
        "- Base: $baseAbs",
        "- Head: $headAbs",
        "- CLI: $cli",
        "- Command: $cmdline",
        "- Exit code: $code",
        "- Diff: $diffStr",
  "- Duration (s): $compareDurationSeconds"
  "- Duration (ns): $compareDurationNanoseconds"
      )
      ($summaryLines -join "`n") | Out-File -FilePath $GitHubStepSummaryPath -Append -Encoding utf8
    }

    if ($diff -and $FailOnDiff) {
      throw 'Differences detected and fail-on-diff=true'
    }

    [pscustomobject]@{
      Base                   = $baseAbs
      Head                   = $headAbs
      Cwd                    = $cwd
      CliPath                = $cli
      Command                = $cmdline
      ExitCode               = $code
      Diff                   = $diff
      CompareDurationSeconds     = $compareDurationSeconds
      CompareDurationNanoseconds = $compareDurationNanoseconds
    }
  }
  finally {
    if ($pushed) { Pop-Location }
  }
}
