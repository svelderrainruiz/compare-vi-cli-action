Describe 'Measure-ResponseWindow script' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Split-Path -Parent $here
    $script = Join-Path $root 'tools' 'Measure-ResponseWindow.ps1'
    $wait = Join-Path $root 'tools' 'Agent-Wait.ps1'
    . $wait
    $global:__scriptPath = $script
  }

  It 'Start then End produces withinMargin = True for close timings' {
    $resultsDir = Join-Path $TestDrive 'measure'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    & $global:__scriptPath -Action Start -Reason 'measure-unit' -ExpectedSeconds 1 -ToleranceSeconds 5 -ResultsDir $resultsDir -Id 'mw1' | Out-Null
    Start-Sleep -Milliseconds 1050
    & $global:__scriptPath -Action End -ResultsDir $resultsDir -ToleranceSeconds 5 -Id 'mw1' -FailOnOutsideMargin:$false | Out-Null

    $sessionDir = Join-Path (Join-Path $resultsDir '_agent') (Join-Path 'sessions' 'mw1')
    $last = Join-Path $sessionDir 'wait-last.json'
    (Test-Path $last) | Should -BeTrue
    $j = Get-Content $last -Raw | ConvertFrom-Json
    $j.withinMargin | Should -BeTrue
  }

  It 'FailOnOutsideMargin sets nonzero exit code when outside' {
    $resultsDir = Join-Path $TestDrive 'measure2'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    & $global:__scriptPath -Action Start -Reason 'measure-unit-2' -ExpectedSeconds 0 -ToleranceSeconds 0 -ResultsDir $resultsDir -Id 'mw2' | Out-Null
    Start-Sleep -Milliseconds 1100
    $exe = (Get-Command pwsh).Source
    $args = @('-NoLogo','-NoProfile','-File', $global:__scriptPath, '-Action','End','-ResultsDir', $resultsDir, '-Id','mw2','-ToleranceSeconds','0','-FailOnOutsideMargin')
    $proc = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $TestDrive 'out.txt')
    $proc.ExitCode | Should -Be 2
  }
}
