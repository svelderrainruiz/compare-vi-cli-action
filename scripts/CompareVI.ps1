set-strictmode -version latest
$ErrorActionPreference = 'Stop'

function Resolve-Cli {
  param(
    [string]$Explicit
  )
  if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return (Resolve-Path -LiteralPath $Explicit).Path }
  if ($env:LVCOMPARE_PATH -and (Test-Path -LiteralPath $env:LVCOMPARE_PATH)) { return (Resolve-Path -LiteralPath $env:LVCOMPARE_PATH).Path }
  $cmd = Get-Command 'LVCompare.exe' -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    'C:\Program Files\NI\LabVIEW 2025\LVCompare.exe',
    'C:\Program Files\National Instruments\LabVIEW 2025\LVCompare.exe',
    'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
  )
  foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
  throw 'LVCompare.exe not found. Provide lvComparePath, set LVCOMPARE_PATH, or ensure it is on PATH. Verifying LabVIEW 2025 Q3 install is recommended.'
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

    $args = @()
    if ($LvCompareArgs) {
      $pattern = '"[^"]+"|\S+'
      $tokens = [regex]::Matches($LvCompareArgs, $pattern) | ForEach-Object { $_.Value }
      foreach ($t in $tokens) { $args += $t.Trim('"') }
    }

    $cmdline = (@(Quote $cli; Quote $baseAbs; Quote $headAbs) + ($args | ForEach-Object { Quote $_ })) -join ' '

    # Execute via injected executor for tests, or call CLI directly
    $code = $null
    if ($Executor) {
      # Pass args as a single array to avoid unrolling
      $code = & $Executor $cli $baseAbs $headAbs ,$args
    }
    else {
      & $cli $baseAbs $headAbs @args
      $code = $LASTEXITCODE
    }

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
      "exitCode=$code"   | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      "cliPath=$cli"     | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      "command=$cmdline" | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
      $diffLower = if ($diff) { 'true' } else { 'false' }
      "diff=$diffLower"  | Out-File -FilePath $GitHubOutputPath -Append -Encoding utf8
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
        "- Diff: $diffStr"
      )
      ($summaryLines -join "`n") | Out-File -FilePath $GitHubStepSummaryPath -Append -Encoding utf8
    }

    if ($diff -and $FailOnDiff) {
      throw 'Differences detected and fail-on-diff=true'
    }

    [pscustomobject]@{
      Base       = $baseAbs
      Head       = $headAbs
      Cwd        = $cwd
      CliPath    = $cli
      Command    = $cmdline
      ExitCode   = $code
      Diff       = $diff
    }
  }
  finally {
    if ($pushed) { Pop-Location }
  }
}
