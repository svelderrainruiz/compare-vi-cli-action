Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'git cat-file path quoting' -Tag 'Integration' {
  It 'handles repository paths containing spaces when working directory supplied' {
    $tempRepo = Join-Path $TestDrive 'space-path-catfile'
    New-Item -ItemType Directory -Path $tempRepo -Force | Out-Null

    Push-Location $tempRepo
    try {
      & git init | Out-Null
      & git config user.name 'CompareVI Tests' | Out-Null
      & git config user.email 'comparevi.tests@example.com' | Out-Null

      $targetRelPath = 'Tooling/deployment/VIP_Post-Install Custom Action.vi'
      New-Item -ItemType Directory -Path (Split-Path -Parent $targetRelPath) -Force | Out-Null

      'base version' | Set-Content -LiteralPath $targetRelPath -Encoding utf8
      & git add . | Out-Null
      & git commit -m 'feat: add VIP post-install action' | Out-Null

      'updated version' | Set-Content -LiteralPath $targetRelPath -Encoding utf8
      & git add . | Out-Null
      & git commit -m 'fix: adjust VIP post-install action' | Out-Null

      $headCommit = (& git rev-parse HEAD).Trim()
      $expr = "{0}:{1}" -f $headCommit, $targetRelPath

      $psi = [System.Diagnostics.ProcessStartInfo]::new()
      $psi.FileName = 'git'
      foreach ($arg in @('cat-file','-e',$expr)) { [void]$psi.ArgumentList.Add($arg) }
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true

      $procNoCwd = [System.Diagnostics.Process]::Start($psi)
      $procNoCwd.WaitForExit()
      $procNoCwd.ExitCode | Should -Not -Be 0

      $psiWorking = [System.Diagnostics.ProcessStartInfo]::new()
      $psiWorking.FileName = 'git'
      foreach ($arg in @('cat-file','-e',$expr)) { [void]$psiWorking.ArgumentList.Add($arg) }
      $psiWorking.RedirectStandardOutput = $true
      $psiWorking.RedirectStandardError = $true
      $psiWorking.UseShellExecute = $false
      $psiWorking.CreateNoWindow = $true
      $psiWorking.WorkingDirectory = $tempRepo

      $procWithCwd = [System.Diagnostics.Process]::Start($psiWorking)
      $procWithCwd.WaitForExit()
      $procWithCwd.ExitCode | Should -Be 0
    }
    finally {
      Pop-Location
    }
  }
}
