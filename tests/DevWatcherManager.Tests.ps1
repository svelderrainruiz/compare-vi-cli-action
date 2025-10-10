Describe 'Dev Watcher Manager' -Tag 'Unit' {
  BeforeAll {
    Get-Command node -ErrorAction Stop | Out-Null
  }

  It 'ensures watcher and reports enriched status' {
    $resultsDir = Join-Path $TestDrive 'results'
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

    pwsh -NoLogo -NoProfile -File tools/Dev-WatcherManager.ps1 -Ensure -ResultsDir $resultsDir -WarnSeconds 1 -HangSeconds 2 -NoProgressSeconds 0 -PollMs 200 | Out-Null
    Start-Sleep -Milliseconds 400

    $statusJson = pwsh -NoLogo -NoProfile -File tools/Dev-WatcherManager.ps1 -Status -ResultsDir $resultsDir
    $status = $statusJson | ConvertFrom-Json

    $status.schema | Should -Be 'dev-watcher/status-v2'
    $status.state | Should -Not -BeNullOrEmpty
    $status.files.status.exists | Should -BeTrue
    $status.files.heartbeat.exists | Should -BeTrue
    $status.lastHeartbeatAt | Should -Not -BeNullOrEmpty
    $status.thresholds | Should -Not -BeNullOrEmpty

    pwsh -NoLogo -NoProfile -File tools/Dev-WatcherManager.ps1 -Stop -ResultsDir $resultsDir | Out-Null
    Start-Sleep -Milliseconds 200

    $afterStop = pwsh -NoLogo -NoProfile -File tools/Dev-WatcherManager.ps1 -Status -ResultsDir $resultsDir | ConvertFrom-Json
    $afterStop.alive | Should -BeFalse
    $afterStop.files.heartbeat.exists | Should -BeFalse
  }
}
