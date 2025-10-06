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
    $root = (Get-Location).Path
    & (Join-Path $root 'tools/Write-RunProvenance.ps1') -ResultsDir $res | Out-Null
    $json = Join-Path $res 'provenance.json'
    Test-Path -LiteralPath $json | Should -BeTrue
    & (Join-Path $root 'tools/Invoke-JsonSchemaLite.ps1') -JsonPath $json -SchemaPath (Join-Path $root 'docs/schemas/run-provenance-v1.schema.json')
    $LASTEXITCODE | Should -Be 0
  }
}

