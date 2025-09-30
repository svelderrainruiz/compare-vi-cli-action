# Requires -Version 5.1
# Pester v5 tests

BeforeAll {
  $here = Split-Path -Parent $PSCommandPath
  $root = Resolve-Path (Join-Path $here '..')
  . (Join-Path $root 'scripts' 'CompareVI.ps1')
}

Describe 'Invoke-CompareVI core behavior' -Tag 'Integration' {
  BeforeEach {
    $TestDrive = Join-Path $env:TEMP ("comparevi-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $TestDrive -Force | Out-Null

    $vis = Join-Path $TestDrive 'vis'
    New-Item -ItemType Directory -Path $vis -Force | Out-Null
    $a = Join-Path $vis 'a.vi'
    $b = Join-Path $vis 'b.vi'
    New-Item -ItemType File -Path $a -Force | Out-Null
    New-Item -ItemType File -Path $b -Force | Out-Null

    $mockDir = Join-Path $TestDrive 'mock'
    New-Item -ItemType Directory -Path $mockDir -Force | Out-Null
    $mockExe = Join-Path $mockDir 'LVCompare.cmd'
    Set-Content -LiteralPath $mockExe -Encoding ASCII -Value @(
      '@echo off',
      'REM Mock LVCompare: exit 0 if base==head; else 1. Allow override via FORCE_EXIT.',
      'if not "%FORCE_EXIT%"=="" exit /b %FORCE_EXIT%',
      'if "%~f1"=="%~f2" exit /b 0',
      'exit /b 1'
    )

    $script:a = $a; $script:b = $b; $script:mock = $mockExe; $script:vis = $vis
  }

  AfterEach {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TestDrive
  }

  It 'returns diff=true when files differ and handles outputs' {
    $out = Join-Path $TestDrive 'out.txt'
    $sum = Join-Path $TestDrive 'summary.md'
    $res = Invoke-CompareVI -Base $a -Head $b -LvComparePath $mock -GitHubOutputPath $out -GitHubStepSummaryPath $sum -FailOnDiff:$false
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue
    (Get-Content $out) | Should -Contain 'diff=true'
    (Get-Content $sum) | Should -Match 'Diff: true'
  }

  It 'throws when fail-on-diff is true but still writes outputs' {
    $out = Join-Path $TestDrive 'out.txt'
    { Invoke-CompareVI -Base $a -Head $b -LvComparePath $mock -GitHubOutputPath $out -FailOnDiff:$true } | Should -Throw
    (Get-Content $out) | Should -Match 'exitCode=1'
  }

  It 'returns diff=false for equal files' {
    $res = Invoke-CompareVI -Base $a -Head $a -LvComparePath $mock -FailOnDiff:$true
    $res.ExitCode | Should -Be 0
    $res.Diff | Should -BeFalse
  }

  It 'handles unknown exit code by throwing but keeps outputs (diff=false)' {
    $out = Join-Path $TestDrive 'out.txt'
    $env:FORCE_EXIT = '2'
    { Invoke-CompareVI -Base $a -Head $b -LvComparePath $mock -GitHubOutputPath $out -FailOnDiff:$false } | Should -Throw
    Remove-Item Env:FORCE_EXIT -ErrorAction SilentlyContinue
    (Get-Content $out) | Should -Contain 'diff=false'
  }

  It 'discovers CLI via LVCOMPARE_PATH env var' {
    $env:LVCOMPARE_PATH = $mock
    $res = Invoke-CompareVI -Base $a -Head $b -FailOnDiff:$false
    Remove-Item Env:LVCOMPARE_PATH -ErrorAction SilentlyContinue
    $res.CliPath | Should -Be (Resolve-Path $mock).Path
  }

  It 'discovers CLI via PATH when not explicitly provided' {
    $env:PATH = (Split-Path -Parent $mock) + ';' + $env:PATH
    $res = Invoke-CompareVI -Base $a -Head $b -FailOnDiff:$false
    $res.CliPath | Should -Match 'LVCompare'
  }

  It 'parses quoted args and reconstructs the command' {
    $res = Invoke-CompareVI -Base $a -Head $b -LvComparePath $mock -LvCompareArgs '--flag "C:\\Temp\\Spaced Path\\x"' -FailOnDiff:$false
    $res.Command | Should -Match '"C:\\Temp\\Spaced Path\\x"'
  }

  It 'resolves relative paths from working-directory' {
    $res = Invoke-CompareVI -Base 'a.vi' -Head 'b.vi' -LvComparePath $mock -WorkingDirectory $vis -FailOnDiff:$false
    $res.Base | Should -Be (Resolve-Path (Join-Path $vis 'a.vi')).Path
    $res.Head | Should -Be (Resolve-Path (Join-Path $vis 'b.vi')).Path
  }

  It 'throws when base or head not found' {
    { Invoke-CompareVI -Base 'missing.vi' -Head $a -LvComparePath $mock } | Should -Throw
    { Invoke-CompareVI -Base $a -Head 'missing.vi' -LvComparePath $mock } | Should -Throw
  }
}
