Describe 'Run Provenance schema' -Tag 'Unit' {
  It 'emits run-provenance/v1 adhering to schema-lite' {
    $res = Join-Path $TestDrive 'results'
    New-Item -ItemType Directory -Force -Path $res | Out-Null
    # Minimal env to generate provenance deterministically
    $env:GITHUB_REF = 'refs/heads/feature/x'
    $env:GITHUB_REF_NAME = 'feature/x'
    $env:GITHUB_WORKFLOW = 'orchestrated'
    $env:GITHUB_EVENT_NAME = 'workflow_dispatch'
    $env:GITHUB_REPOSITORY = 'owner/repo'
    $env:GITHUB_RUN_ID = '1'
    $env:GITHUB_RUN_ATTEMPT = '1'
    $env:GITHUB_SHA = 'deadbeef'
    $origRunner = @{
      RUNNER_NAME        = $env:RUNNER_NAME
      RUNNER_OS          = $env:RUNNER_OS
      RUNNER_ARCH        = $env:RUNNER_ARCH
      RUNNER_LABELS      = $env:RUNNER_LABELS
      RUNNER_ENVIRONMENT = $env:RUNNER_ENVIRONMENT
      RUNNER_TRACKING_ID = $env:RUNNER_TRACKING_ID
      GITHUB_JOB         = $env:GITHUB_JOB
      ImageOS            = $env:ImageOS
      ImageVersion       = $env:ImageVersion
    }
    try {
      $env:RUNNER_NAME = 'schema-runner'
      $env:RUNNER_OS = 'Windows'
      $env:RUNNER_ARCH = 'X64'
      $env:GITHUB_JOB = 'schema-job'
      $env:RUNNER_ENVIRONMENT = 'self-hosted'
      $env:RUNNER_TRACKING_ID = 'schema-tracking'
      $env:RUNNER_LABELS = 'self-hosted,windows'
      $env:ImageOS = 'windows-server-2022'
      $env:ImageVersion = '2025.10.0'

      $root = (Get-Location).Path
      & (Join-Path $root 'tools/Write-RunProvenance.ps1') -ResultsDir $res | Out-Null
      $json = Join-Path $res 'provenance.json'
      Test-Path -LiteralPath $json | Should -BeTrue
      & (Join-Path $root 'tools/Invoke-JsonSchemaLite.ps1') -JsonPath $json -SchemaPath (Join-Path $root 'docs/schemas/run-provenance-v1.schema.json')
      $LASTEXITCODE | Should -Be 0
    } finally {
      foreach ($key in $origRunner.Keys) {
        if ($null -ne $origRunner[$key]) {
          Set-Item -Path Env:$key -Value $origRunner[$key]
        } else {
          Remove-Item -Path Env:$key -ErrorAction SilentlyContinue
        }
      }
    }
  }
}
