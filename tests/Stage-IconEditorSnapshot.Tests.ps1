$ErrorActionPreference = 'Stop'

Describe 'Stage-IconEditorSnapshot.ps1' -Tag 'IconEditor','Snapshot','Unit' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        Set-Variable -Scope Script -Name repoRoot -Value $repoRoot
        Set-Variable -Scope Script -Name stageScript -Value (Join-Path $repoRoot 'tools/icon-editor/Stage-IconEditorSnapshot.ps1')
        Set-Variable -Scope Script -Name vendorPath -Value (Join-Path $repoRoot 'vendor/icon-editor')

        Test-Path -LiteralPath $script:stageScript | Should -BeTrue
        Test-Path -LiteralPath $script:vendorPath | Should -BeTrue
    }

    It 'stages a snapshot using an existing source and skips validation' {
        $workspaceRoot = Join-Path $TestDrive 'workspace'
        $result = & $script:stageScript `
            -SourcePath $script:vendorPath `
            -WorkspaceRoot $workspaceRoot `
            -StageName 'unit-snapshot' `
            -SkipValidate

        $result | Should -Not -BeNullOrEmpty
        $result.stageRoot | Should -Match 'unit-snapshot$'
        Test-Path -LiteralPath $result.stageRoot -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $result.resourceOverlay -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $result.headManifestPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.headReportPath -PathType Leaf | Should -BeTrue
        $result.validateRoot | Should -BeNullOrEmpty

        $manifest = Get-Content -LiteralPath $result.headManifestPath -Raw | ConvertFrom-Json -Depth 10
        $manifest.schema | Should -Be 'icon-editor/fixture-manifest@v1'
        ($manifest.entries | Measure-Object).Count | Should -BeGreaterThan 0

        $report = Get-Content -LiteralPath $result.headReportPath -Raw | ConvertFrom-Json -Depth 10
        $report.schema | Should -Be 'icon-editor/fixture-report@v1'
    }

    It 'invokes the provided validate helper with dry-run semantics' {
        $workspaceRoot = Join-Path $TestDrive 'workspace'
        $validateStubDir = Join-Path $TestDrive 'validate-stub'
        $null = New-Item -ItemType Directory -Path $validateStubDir -Force
        $logPath = Join-Path $validateStubDir 'log.json'
        $validateStub = Join-Path $validateStubDir 'Invoke-ValidateLocal.ps1'
$stubTemplate = @'
param(
  [string]$BaselineFixture,
  [string]$BaselineManifest,
  [string]$ResourceOverlayRoot,
  [string]$ResultsRoot,
  [switch]$SkipLVCompare,
  [switch]$DryRun,
  [switch]$SkipBootstrap
)
$payload = [ordered]@{
  baselineFixture  = $BaselineFixture
  baselineManifest = $BaselineManifest
  resourceOverlay  = $ResourceOverlayRoot
  resultsRoot      = $ResultsRoot
  skipLVCompare    = $SkipLVCompare.IsPresent
  dryRun           = $DryRun.IsPresent
  skipBootstrap    = $SkipBootstrap.IsPresent
}
$payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "__LOG_PATH__" -Encoding utf8
'@
$stubTemplate.Replace('__LOG_PATH__', $logPath) | Set-Content -LiteralPath $validateStub -Encoding utf8

        $result = & $script:stageScript `
            -SourcePath $script:vendorPath `
            -WorkspaceRoot $workspaceRoot `
            -StageName 'unit-dryrun' `
            -InvokeValidateScript $validateStub `
            -DryRun `
            -SkipBootstrapForValidate

        $result | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $result.validateRoot -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $logPath -PathType Leaf | Should -BeTrue

        $log = Get-Content -LiteralPath $logPath -Raw | ConvertFrom-Json -Depth 4
        $log.resultsRoot | Should -Be $result.validateRoot
        ($log.skipLVCompare -eq $true) | Should -BeTrue
        ($log.dryRun -eq $true) | Should -BeTrue
        ($log.skipBootstrap -eq $true) | Should -BeTrue
        Test-Path -LiteralPath $log.resourceOverlay -PathType Container | Should -BeTrue
    }
}
