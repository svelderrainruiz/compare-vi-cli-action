Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Invoke-LVCompare.ps1' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:driverPath = Join-Path $repoRoot 'tools' 'Invoke-LVCompare.ps1'
    Test-Path -LiteralPath $script:driverPath | Should -BeTrue
  }

  It 'writes capture and includes default flags with leak summary' {
    $work = Join-Path $TestDrive 'driver-default'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $captureStub = Join-Path $work 'CaptureStub.ps1'
      $stub = @'
param(
  [string]$Base,
  [string]$Head,
  [object]$LvArgs,
  [string]$LvComparePath,
  [switch]$RenderReport,
  [string]$OutputDir,
  [switch]$Quiet
)
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if ($LvArgs -is [System.Array]) { $args = @($LvArgs) } elseif ($LvArgs) { $args = @([string]$LvArgs) } else { $args = @() }
$cap = [ordered]@{ schema='lvcompare-capture-v1'; exitCode=1; seconds=0.5; command='stub'; args=$args }
$cap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'lvcompare-capture.json') -Encoding utf8
exit 1
'@
      Set-Content -LiteralPath $captureStub -Value $stub -Encoding UTF8

      $labviewExe = Join-Path $work 'LabVIEW.exe'; Set-Content -LiteralPath $labviewExe -Encoding ascii -Value ''
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Encoding ascii -Value ''
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Encoding ascii -Value ''
      $outDir = Join-Path $work 'out'
      $logPath = Join-Path $outDir 'events.ndjson'

      $driverQuoted = $script:driverPath.Replace("'", "''")
      $baseQuoted = $base.Replace("'", "''")
      $headQuoted = $head.Replace("'", "''")
      $labviewQuoted = $labviewExe.Replace("'", "''")
      $outQuoted = $outDir.Replace("'", "''")
      $logQuoted = $logPath.Replace("'", "''")
      $stubQuoted = $captureStub.Replace("'", "''")
      $command = "& { & '$driverQuoted' -BaseVi '$baseQuoted' -HeadVi '$headQuoted' -LabVIEWExePath '$labviewQuoted' -OutputDir '$outQuoted' -JsonLogPath '$logQuoted' -LeakCheck -CaptureScriptPath '$stubQuoted'; exit `$LASTEXITCODE }"
      & pwsh -NoLogo -NoProfile -Command $command *> $null

      $LASTEXITCODE | Should -Be 1
      $capturePath = Join-Path $outDir 'lvcompare-capture.json'
      Test-Path -LiteralPath $capturePath | Should -BeTrue
      $cap = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
      $cap.args | Should -Contain '-nobdcosm'
      $cap.args | Should -Contain '-nofppos'
      $cap.args | Should -Contain '-noattr'
    }
    finally { Pop-Location }
  }

  It 'supports ReplaceFlags to override defaults' {
    $work = Join-Path $TestDrive 'driver-custom'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $captureStub = Join-Path $work 'CaptureStub.ps1'
      $stub = @'
param(
  [string]$Base,
  [string]$Head,
  [object]$LvArgs,
  [string]$LvComparePath,
  [switch]$RenderReport,
  [string]$OutputDir,
  [switch]$Quiet
)
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if ($LvArgs -is [System.Array]) { $args = @($LvArgs) } elseif ($LvArgs) { $args = @([string]$LvArgs) } else { $args = @() }
$cap = [ordered]@{ schema='lvcompare-capture-v1'; exitCode=0; seconds=0.25; command='stub'; args=$args }
$cap | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'lvcompare-capture.json') -Encoding utf8
exit 0
'@
      Set-Content -LiteralPath $captureStub -Value $stub -Encoding UTF8

      $labviewExe = Join-Path $work 'LabVIEW.exe'; Set-Content -LiteralPath $labviewExe -Encoding ascii -Value ''
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Encoding ascii -Value ''
$head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Encoding ascii -Value ''
      $outDir = Join-Path $work 'out'

      $logPath = Join-Path $outDir 'events.ndjson'
      $driverQuoted = $script:driverPath.Replace("'", "''")
      $baseQuoted = $base.Replace("'", "''")
      $headQuoted = $head.Replace("'", "''")
      $labviewQuoted = $labviewExe.Replace("'", "''")
      $outQuoted = $outDir.Replace("'", "''")
      $logQuoted = $logPath.Replace("'", "''")
      $stubQuoted = $captureStub.Replace("'", "''")
      $flagsCommand = "-Flags @('alpha','beta','gamma')"
      $command = "& { & '$driverQuoted' -BaseVi '$baseQuoted' -HeadVi '$headQuoted' -LabVIEWExePath '$labviewQuoted' -OutputDir '$outQuoted' $flagsCommand -ReplaceFlags -JsonLogPath '$logQuoted' -CaptureScriptPath '$stubQuoted'; exit `$LASTEXITCODE }"
      & pwsh -NoLogo -NoProfile -Command $command *> $null

      $exitCode = $LASTEXITCODE
      $exitCode | Should -Be 0
      $cap = Get-Content -LiteralPath (Join-Path $outDir 'lvcompare-capture.json') -Raw | ConvertFrom-Json
      ($cap.args -contains '-nobdcosm') | Should -BeFalse
      ($cap.args -contains '-nofppos') | Should -BeFalse
      ($cap.args -contains '-noattr') | Should -BeFalse
      $cap.args | Should -Contain 'alpha'
      $cap.args | Should -Contain 'beta'
      $cap.args | Should -Contain 'gamma'
    }
    finally { Pop-Location }
  }

  It 'annotates capture failures with Source Control hint' {
    $work = Join-Path $TestDrive 'driver-scc-hint'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $captureStub = Join-Path $work 'CaptureStubFail.ps1'
      $stub = @'
param(
  [string]$Base,
  [string]$Head,
  [object]$LvArgs,
  [string]$LvComparePath,
  [switch]$RenderReport,
  [string]$OutputDir,
  [switch]$Quiet
)
throw (New-Object System.Management.Automation.PropertyNotFoundException "The property 'Count' cannot be found on this object. Verify that the property exists.")
'@
      Set-Content -LiteralPath $captureStub -Value $stub -Encoding UTF8

      $labviewExe = Join-Path $work 'LabVIEW.exe'; Set-Content -LiteralPath $labviewExe -Encoding ascii -Value ''
      $lvcompareExe = Join-Path $work 'LVCompare.exe'; Set-Content -LiteralPath $lvcompareExe -Encoding ascii -Value ''
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Encoding ascii -Value ''
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Encoding ascii -Value ''
      $outDir = Join-Path $work 'out'
      New-Item -ItemType Directory -Path $outDir | Out-Null
      $logPath = Join-Path $outDir 'events.ndjson'

      $errorRecord = {
        & $script:driverPath `
          -BaseVi $base -HeadVi $head `
          -LabVIEWExePath $labviewExe `
          -LVComparePath $lvcompareExe `
          -OutputDir $outDir `
          -JsonLogPath $logPath `
          -CaptureScriptPath $captureStub `
          -Quiet
      } | Should -Throw -PassThru

      $errorRecord.Exception.Message | Should -Match 'SCC_ConnSrv'
      $errorRecord.Exception.Message | Should -Match 'Error 1025'
      Test-Path -LiteralPath $logPath | Should -BeTrue
      $lines = Get-Content -LiteralPath $logPath
      ($lines | Where-Object { $_ -match 'SCC_ConnSrv' }).Count | Should -BeGreaterThan 0
    }
    finally { Pop-Location }
  }

  It 'emits the SCC hint without noise suppression' {
    $work = Join-Path $TestDrive 'driver-scc-hint-noisy'
    New-Item -ItemType Directory -Path $work | Out-Null
    Push-Location $work
    try {
      $captureStub = Join-Path $work 'CaptureStubFail.ps1'
      $stub = @'
param(
  [string]$Base,
  [string]$Head,
  [object]$LvArgs,
  [string]$LvComparePath,
  [switch]$RenderReport,
  [string]$OutputDir,
  [switch]$Quiet
)
throw (New-Object System.Management.Automation.PropertyNotFoundException "The property 'Count' cannot be found on this object. Verify that the property exists.")
'@
      Set-Content -LiteralPath $captureStub -Value $stub -Encoding UTF8

      $labviewExe = Join-Path $work 'LabVIEW.exe'; Set-Content -LiteralPath $labviewExe -Encoding ascii -Value ''
      $lvcompareExe = Join-Path $work 'LVCompare.exe'; Set-Content -LiteralPath $lvcompareExe -Encoding ascii -Value ''
      $base = Join-Path $work 'Base.vi'; Set-Content -LiteralPath $base -Encoding ascii -Value ''
      $head = Join-Path $work 'Head.vi'; Set-Content -LiteralPath $head -Encoding ascii -Value ''
      $outDir = Join-Path $work 'out'
      New-Item -ItemType Directory -Path $outDir | Out-Null
      $logPath = Join-Path $outDir 'events.ndjson'

      $driverQuoted = $script:driverPath.Replace("'", "''")
      $baseQuoted = $base.Replace("'", "''")
      $headQuoted = $head.Replace("'", "''")
      $labviewQuoted = $labviewExe.Replace("'", "''")
      $lvcompareQuoted = $lvcompareExe.Replace("'", "''")
      $outQuoted = $outDir.Replace("'", "''")
      $logQuoted = $logPath.Replace("'", "''")
      $stubQuoted = $captureStub.Replace("'", "''")
      $command = "& { & '$driverQuoted' -BaseVi '$baseQuoted' -HeadVi '$headQuoted' -LabVIEWExePath '$labviewQuoted' -LVComparePath '$lvcompareQuoted' -OutputDir '$outQuoted' -JsonLogPath '$logQuoted' -CaptureScriptPath '$stubQuoted'; exit `$LASTEXITCODE }"

      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = 'pwsh'
      $psi.ArgumentList.Add('-NoLogo') | Out-Null
      $psi.ArgumentList.Add('-NoProfile') | Out-Null
      $psi.ArgumentList.Add('-Command') | Out-Null
      $psi.ArgumentList.Add($command) | Out-Null
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.UseShellExecute = $false

      $process = [System.Diagnostics.Process]::Start($psi)
      $stdout = $process.StandardOutput.ReadToEnd()
      $stderr = $process.StandardError.ReadToEnd()
      $process.WaitForExit()

      $process.ExitCode | Should -Be 1
      $combined = ($stdout + "`n" + $stderr)
      $combined | Should -Match 'SCC_ConnSrv'
      $combined | Should -Match 'Likely cause'
    }
    finally { Pop-Location }
  }
}
