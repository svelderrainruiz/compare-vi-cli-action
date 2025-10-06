Describe 'Write-RunProvenance' -Tag 'Unit' {
  BeforeAll {
    $script:orig = @{
      GITHUB_REF          = $env:GITHUB_REF
      GITHUB_REF_NAME     = $env:GITHUB_REF_NAME
      GITHUB_HEAD_REF     = $env:GITHUB_HEAD_REF
      GITHUB_BASE_REF     = $env:GITHUB_BASE_REF
      GITHUB_EVENT_NAME   = $env:GITHUB_EVENT_NAME
      GITHUB_EVENT_PATH   = $env:GITHUB_EVENT_PATH
      GITHUB_REPOSITORY   = $env:GITHUB_REPOSITORY
      GITHUB_RUN_ID       = $env:GITHUB_RUN_ID
      GITHUB_RUN_ATTEMPT  = $env:GITHUB_RUN_ATTEMPT
      GITHUB_WORKFLOW     = $env:GITHUB_WORKFLOW
      GITHUB_SHA          = $env:GITHUB_SHA
    }
  }

  AfterAll {
    foreach ($k in $script:orig.Keys) {
      if ($null -ne $script:orig[$k]) { Set-Item -Path Env:$k -Value $script:orig[$k] } else { Remove-Item Env:$k -ErrorAction SilentlyContinue }
    }
  }

  It 'falls back to refName when headRef is empty (workflow_dispatch)' {
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    $env:GITHUB_REF        = 'refs/heads/feature/fallback'
    $env:GITHUB_REF_NAME   = 'feature/fallback'
    Remove-Item Env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_BASE_REF -ErrorAction SilentlyContinue
    $env:GITHUB_REPOSITORY = 'owner/repo'
    $env:GITHUB_RUN_ID = '1234'
    $env:GITHUB_RUN_ATTEMPT = '1'
    $env:GITHUB_WORKFLOW = 'orchestrated'
    $env:GITHUB_SHA = 'deadbeef'

    $outDir = Join-Path $TestDrive 'results'
    $root = (Get-Location).Path
    & (Join-Path $root 'tools/Write-RunProvenance.ps1') -ResultsDir $outDir
    $p = Get-Content -LiteralPath (Join-Path $outDir 'provenance.json') -Raw | ConvertFrom-Json
    $p.branch | Should -Be 'feature/fallback'
    $p.refName | Should -Be 'feature/fallback'
    $p.headRef | Should -Be 'feature/fallback'
    $p.baseRef | Should -Be ''
  }

  It 'uses PR event payload head/base refs and prNumber (pull_request)' {
    $env:GITHUB_EVENT_NAME = 'pull_request'
    $env:GITHUB_REF        = 'refs/pull/123/merge'
    $env:GITHUB_REF_NAME   = 'feature/from-pr'
    $evt = @{
      pull_request = @{ number = 123; head = @{ ref = 'feature/from-pr' }; base = @{ ref = 'develop' } }
    } | ConvertTo-Json
    $evtPath = Join-Path $TestDrive 'event.json'
    Set-Content -LiteralPath $evtPath -Value $evt -Encoding UTF8
    $env:GITHUB_EVENT_PATH = $evtPath
    Remove-Item Env:GITHUB_HEAD_REF -ErrorAction SilentlyContinue
    Remove-Item Env:GITHUB_BASE_REF -ErrorAction SilentlyContinue

    $outDir = Join-Path $TestDrive 'results2'
    $root = (Get-Location).Path
    & (Join-Path $root 'tools/Write-RunProvenance.ps1') -ResultsDir $outDir
    $p = Get-Content -LiteralPath (Join-Path $outDir 'provenance.json') -Raw | ConvertFrom-Json
    $p.prNumber | Should -Be 123
    $p.headRef  | Should -Be 'feature/from-pr'
    $p.baseRef  | Should -Be 'develop'
  }
}

