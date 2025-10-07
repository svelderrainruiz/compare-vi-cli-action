Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Updater wire probes injection' -Tag 'Unit' {
  BeforeAll {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:upd = (Join-Path $root 'tools' 'workflows' 'update_workflows.py')
    if (-not (Test-Path -LiteralPath $script:upd)) { throw "Updater script not found: $script:upd" }
  }

  It 'injects J1/J2, T1, S1, C1/C2, I1/I2, G0/G1, P1 in ci-orchestrated.yml' {
    $wf = @'
name: CI Orchestrated (deterministic chain)
on: { workflow_dispatch: {} }
jobs:
  pester-category:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v5
    - name: Run Pester tests via local dispatcher (category)
      run: echo run
    - name: Session index post
      uses: ./.github/actions/session-index-post
  drift:
    runs-on: [self-hosted, Windows, X64]
    steps:
    - uses: actions/checkout@v5
    - name: Runner Unblock Guard
      uses: ./.github/actions/runner-unblock-guard
    - name: Drift (fixture)
      uses: ./.github/actions/fixture-drift
    - name: Ensure Invoker (start)
      uses: ./.github/actions/ensure-invoker
      with: { mode: start }
    - name: Ensure Invoker (stop)
      uses: ./.github/actions/ensure-invoker
      with: { mode: stop }
  publish:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v5
    - name: Summarize orchestrated run
      run: echo sum
'@
    $p = Join-Path $TestDrive 'ci-orchestrated.yml'
    Set-Content -LiteralPath $p -Value $wf -Encoding UTF8
    # Apply updater
    $null = & python $script:upd --write $p
    $doc = Get-Content -LiteralPath $p -Raw | ConvertFrom-Yaml
    $pc = $doc.jobs.'pester-category'.steps
    $pcNames = @($pc | ForEach-Object { $_.name })
    $pcNames | Should -Contain 'Wire Probe (J1)'
    $pcNames | Should -Contain 'Wire Probe (J2)'
    $pcNames | Should -Contain 'Wire Probe (T1)'
    # S1 before session index
    $pcNames | Should -Contain 'Wire Session Index (S1)'
    # Results dir on matrix
    $s1 = $pc | Where-Object { $_.name -eq 'Wire Session Index (S1)' } | Select-Object -First 1
    $s1.with.'results-dir' | Should -Be 'tests/results/${{ matrix.category }}'

    # Drift job C1/C2 and guard/invoker
    $dr = $doc.jobs.drift.steps
    @($dr | % { $_.name }) | Should -Contain 'Wire Probe (C1)'
    @($dr | % { $_.name }) | Should -Contain 'Wire Probe (C2)'
    @($dr | % { $_.name }) | Should -Contain 'Wire Guard (pre)'
    @($dr | % { $_.name }) | Should -Contain 'Wire Guard (post)'
    @($dr | % { $_.name }) | Should -Contain 'Wire Invoker (start)'
    @($dr | % { $_.name }) | Should -Contain 'Wire Invoker (stop)'

    # Publish P1
    $pub = $doc.jobs.publish.steps
    @($pub | % { $_.name }) | Should -Contain 'Wire Probe (P1)'
  }

  It 'injects J1/J2 and S1 in validate.yml and is idempotent' {
    $wf = @'
name: Validate
on: { workflow_dispatch: {} }
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v5
    - name: Session index post
      uses: ./.github/actions/session-index-post
'@
    $p = Join-Path $TestDrive 'validate.yml'
    Set-Content -LiteralPath $p -Value $wf -Encoding UTF8
    # Run twice to ensure no duplicates
    $null = & python $script:upd --write $p
    $null = & python $script:upd --write $p
    $doc = Get-Content -LiteralPath $p -Raw | ConvertFrom-Yaml
    $steps = $doc.jobs.lint.steps
    $names = @($steps | % { $_.name })
    ($names | Where-Object { $_ -eq 'Wire Probe (J1)' }).Count | Should -Be 1
    ($names | Where-Object { $_ -eq 'Wire Probe (J2)' }).Count | Should -Be 1
    ($names | Where-Object { $_ -eq 'Wire Session Index (S1)' }).Count | Should -Be 1
  }
}

