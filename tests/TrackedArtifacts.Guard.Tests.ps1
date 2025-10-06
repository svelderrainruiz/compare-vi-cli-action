Describe 'Tracked Build Artifacts Guard' -Tag 'Unit' {
  BeforeAll {
    $script:root = (Get-Location).Path
    $script:guard = Join-Path $script:root 'tools/Check-TrackedBuildArtifacts.ps1'
    $script:repo = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Force -Path $script:repo | Out-Null
    Push-Location $script:repo
    git init | Out-Null
    # Create offending tracked files
    New-Item -ItemType Directory -Force -Path 'src/Proj/obj' | Out-Null
    New-Item -ItemType Directory -Force -Path 'src/Legacy/bin/keep' | Out-Null
    Set-Content -LiteralPath 'src/Proj/obj/junk.txt' -Value 'x' -Encoding UTF8
    Set-Content -LiteralPath 'src/Legacy/bin/keep/ok.txt' -Value 'y' -Encoding UTF8
    git add -A | Out-Null
    git -c user.email=test@example.com -c user.name=test commit -m "add offenders" | Out-Null
  }

  AfterAll {
    Pop-Location
  }

  It 'exits with code 3 when tracked offenders exist' {
    $cmd = "pwsh -NoLogo -NoProfile -File `"$script:guard`""
    $pr = Start-Process pwsh -ArgumentList @('-NoLogo','-NoProfile','-Command', $cmd) -Wait -PassThru -WorkingDirectory $script:repo
    $pr.ExitCode | Should -Be 3
  }

  It 'respects file-based allowlist' {
    $allow = Join-Path $script:repo '.ci/build-artifacts-allow.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path $allow -Parent) | Out-Null
    # Allow bin path only; obj should still fail
    @(
      '# allow bin paths',
      'src/Legacy/**/bin/**'
    ) | Set-Content -LiteralPath $allow -Encoding UTF8
    $cmd = "pwsh -NoLogo -NoProfile -File `"$script:guard`" -AllowListPath `"$allow`""
    $pr = Start-Process pwsh -ArgumentList @('-NoLogo','-NoProfile','-Command', $cmd) -Wait -PassThru -WorkingDirectory $script:repo
    $pr.ExitCode | Should -Be 3
  }

  It 'passes when all offenders are allowlisted' {
    $allow = Join-Path $script:repo '.ci/build-artifacts-allow.txt'
    @(
      'src/**/obj/**',
      'src/**/bin/**'
    ) | Set-Content -LiteralPath $allow -Encoding UTF8
    $cmd = "pwsh -NoLogo -NoProfile -File `"$script:guard`" -AllowListPath `"$allow`""
    $pr = Start-Process pwsh -ArgumentList @('-NoLogo','-NoProfile','-Command', $cmd) -Wait -PassThru -WorkingDirectory $script:repo
    $pr.ExitCode | Should -Be 0
  }
}

