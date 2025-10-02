#Requires -Version 7.0
# Tag: Integration (executes the real CLI on self-hosted)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
  Integration test prerequisites initialization is inlined (previous helper function removed)
  to avoid any discovery-time CommandNotFound issues in certain Pester execution contexts.
  Variables are script-scoped so -Skip expressions can safely reference them during discovery.
#>
$script:LabVIEWCLIAvailable = $false
$script:CompareVIPrereqsAvailable = $false
$script:Canonical = 'C:\Program Files\National Instruments\Shared\LabVIEW Compare\LVCompare.exe'
$script:BaseVi = $env:LV_BASE_VI
$script:HeadVi = $env:LV_HEAD_VI
try {
  $canonicalExists = Test-Path -LiteralPath $script:Canonical -PathType Leaf
  $baseOk = ($script:BaseVi) -and (-not [string]::IsNullOrWhiteSpace($script:BaseVi)) -and (Test-Path -LiteralPath $script:BaseVi -PathType Leaf)
  $headOk = ($script:HeadVi) -and (-not [string]::IsNullOrWhiteSpace($script:HeadVi)) -and (Test-Path -LiteralPath $script:HeadVi -PathType Leaf)
  if ($canonicalExists -and $baseOk -and $headOk) { $script:CompareVIPrereqsAvailable = $true }
} catch {
  # Never let initialization errors break discovery; leave CompareVIPrereqsAvailable = $false for skipping
  Write-Verbose "Integration prereq initialization suppressed error: $($_.Exception.Message)" -Verbose
}

BeforeAll {
  $here = Split-Path -Parent $PSCommandPath
  $repoRoot = Resolve-Path (Join-Path $here '..')
  . (Join-Path $repoRoot 'scripts' 'CompareVI.ps1')
  # Create results directory once for all integration tests
  $ResultsDir = Join-Path $here 'results'
  New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
  $script:ResultsDir = $ResultsDir
}

Describe 'Invoke-CompareVI (real CLI on self-hosted)' -Tag Integration {
  It 'prerequisites available (skip remaining if not)' {
    $prereq = $false
    try {
      $var = Get-Variable -Name CompareVIPrereqsAvailable -Scope Script -ErrorAction Stop
      $prereq = [bool]$var.Value
    } catch {
      $prereq = $false
    }
    if (-not $prereq) {
      Write-Host "INFO: CompareVI integration prerequisites not satisfied (CLI or VI paths missing). Skipping remaining tests in this block." -ForegroundColor Yellow
      Set-ItResult -Skipped -Because 'CompareVI prerequisites not satisfied'
      return
    }
    $prereq | Should -BeTrue
  }

  It 'exit 0 => diff=false when base=head' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    $res = Invoke-CompareVI -Base $BaseVi -Head $BaseVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 0
    $res.Diff | Should -BeFalse
    $res.CliPath | Should -Be (Resolve-Path $Canonical).Path
  }

  It 'exit 1 => diff=true when base!=head' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    $res = Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue
  }

  It 'fail-on-diff=true throws after outputs are written for diff' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    $tmpOut = Join-Path $env:TEMP ("comparevi-outputs-{0}.txt" -f ([guid]::NewGuid()))
    { Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -GitHubOutputPath $tmpOut -FailOnDiff:$true } | Should -Throw
    (Get-Content -LiteralPath $tmpOut -Raw) | Should -Match '(^|\n)diff=true($|\n)'
    Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
  }

  It 'generates HTML report from real comparison results' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    # Run comparison (with diff expected)
    $res = Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -FailOnDiff:$false
    $res.ExitCode | Should -Be 1
    $res.Diff | Should -BeTrue

    # Generate HTML report
    $htmlPath = Join-Path $ResultsDir 'integration-compare-report.html'
    
    $renderer = Join-Path (Split-Path -Parent $here) 'scripts' 'Render-CompareReport.ps1'
    & $renderer `
      -Command $res.Command `
      -ExitCode $res.ExitCode `
      -Diff ($res.Diff.ToString().ToLower()) `
      -CliPath $res.CliPath `
      -OutputPath $htmlPath

    # Verify HTML was created
    Test-Path -LiteralPath $htmlPath | Should -BeTrue
    
    # Verify HTML contains expected content
    $html = Get-Content -LiteralPath $htmlPath -Raw
    $html | Should -Match 'Compare VI Report'
    $html | Should -Match 'Differences detected'
    $html | Should -Match 'Exit code.*1'
  }

  It 'accepts recommended knowledgebase CLI flags: -nobdcosm -nofppos -noattr' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    # Test with recommended noise filters from knowledgebase
    $cliArgs = '-nobdcosm -nofppos -noattr'
    $res = Invoke-CompareVI -Base $BaseVi -Head $HeadVi -LvComparePath $Canonical -LvCompareArgs $cliArgs -FailOnDiff:$false
    
    # Should execute successfully with these flags
    $res.ExitCode | Should -BeIn @(0, 1)
    
    # Verify flags are in the command
    $res.Command | Should -Match '-nobdcosm'
    $res.Command | Should -Match '-nofppos'
    $res.Command | Should -Match '-noattr'
  }

  It 'handles -lvpath flag from knowledgebase for LabVIEW version selection' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    # Note: This test verifies the flag is passed correctly, but doesn't require LabVIEW.exe to exist
    # The actual LabVIEW path may not exist on the test runner
    $lvPath = 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe'
  $cliArgs = "-lvpath `"$lvPath`""
    
  $res = Invoke-CompareVI -Base $BaseVi -Head $BaseVi -LvComparePath $Canonical -LvCompareArgs $cliArgs -FailOnDiff:$false
    
    # Should execute (may fail if LabVIEW.exe doesn't exist, but that's OK for this test)
    # We're just verifying the argument is passed correctly
    $res.Command | Should -Match '-lvpath'
    $res.Command | Should -Match [regex]::Escape($lvPath)
  }

  It 'handles complex flag combinations from knowledgebase' -Skip:(-not $script:CompareVIPrereqsAvailable) {
    # Combine multiple recommended flags
    $lvPath = 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEW.exe'
  $cliArgs = "-lvpath `"$lvPath`" -nobdcosm -nofppos -noattr"
    
  $res = Invoke-CompareVI -Base $BaseVi -Head $BaseVi -LvComparePath $Canonical -LvCompareArgs $cliArgs -FailOnDiff:$false
    
    # Verify all flags are in the command
    $res.Command | Should -Match '-lvpath'
    $res.Command | Should -Match '-nobdcosm'
    $res.Command | Should -Match '-nofppos'
    $res.Command | Should -Match '-noattr'
  }
}

Describe 'LabVIEWCLI HTML Comparison Report Generation' -Tag Integration {
  BeforeAll {
    # Common paths for LabVIEW 2025
    $LabVIEWCLI64 = 'C:\Program Files\National Instruments\LabVIEW 2025\LabVIEWCLI.exe'
    $LabVIEWCLI32 = 'C:\Program Files (x86)\National Instruments\LabVIEW 2025\LabVIEWCLI.exe'
    
    # Try to find LabVIEWCLI
    $script:LabVIEWCLI = $null
    if (Test-Path -LiteralPath $LabVIEWCLI64 -PathType Leaf) {
      $script:LabVIEWCLI = $LabVIEWCLI64
    } elseif (Test-Path -LiteralPath $LabVIEWCLI32 -PathType Leaf) {
      $script:LabVIEWCLI = $LabVIEWCLI32
    }
    
    # Flag to skip tests if LabVIEWCLI not available
    $script:LabVIEWCLIAvailable = $null -ne $script:LabVIEWCLI
  }

  It 'has LabVIEWCLI available (skip remaining tests if not)' {
    if (-not $LabVIEWCLIAvailable) {
      Write-Host "INFO: LabVIEWCLI.exe not found. Skipping LabVIEWCLI HTML report tests."
      Write-Host "Install LabVIEW 2025 Q3 or later with LabVIEWCLI to enable these tests."
      Set-ItResult -Skipped -Because "LabVIEWCLI not installed"
    }
    $LabVIEWCLIAvailable | Should -BeTrue
  }

  It 'generates HTML report with CreateComparisonReport operation' -Skip:(-not $script:LabVIEWCLIAvailable) {
    $reportPath = Join-Path $ResultsDir 'labviewcli-comparison-report.html'
    
    # Execute LabVIEWCLI with CreateComparisonReport operation
  $cliArgs = @(
      '-OperationName', 'CreateComparisonReport',
      '-vi1', $BaseVi,
      '-vi2', $HeadVi,
      '-reportType', 'HTMLSingleFile',
      '-reportPath', $reportPath
    )
    
  & $LabVIEWCLI @cliArgs
    $exitCode = $LASTEXITCODE
    
    # Verify the command executed successfully
    $exitCode | Should -Be 0
    
    # Verify HTML report was created
    Test-Path -LiteralPath $reportPath | Should -BeTrue
    
    # Verify HTML contains expected content
    $html = Get-Content -LiteralPath $reportPath -Raw
    $html | Should -Not -BeNullOrEmpty
    # HTML should contain some comparison-related content
    $html | Should -Match '(?i)(compare|comparison|difference|diff|vi)'
  }

  It 'generates HTML report with noise filter flags from knowledgebase' -Skip:(-not $script:LabVIEWCLIAvailable) {
    $reportPath = Join-Path $ResultsDir 'labviewcli-comparison-report-filtered.html'
    
    # Execute LabVIEWCLI with recommended noise filter flags
  $cliArgs = @(
      '-OperationName', 'CreateComparisonReport',
      '-vi1', $BaseVi,
      '-vi2', $HeadVi,
      '-reportType', 'HTMLSingleFile',
      '-reportPath', $reportPath,
      '-nobdcosm',  # Ignore block diagram cosmetic changes
      '-nofppos',   # Ignore front panel position changes
      '-noattr'     # Ignore VI attribute changes
    )
    
  & $LabVIEWCLI @cliArgs
    $exitCode = $LASTEXITCODE
    
    # Verify the command executed successfully
    $exitCode | Should -Be 0
    
    # Verify HTML report was created
    Test-Path -LiteralPath $reportPath | Should -BeTrue
    
    # Verify HTML is valid
    $html = Get-Content -LiteralPath $reportPath -Raw
    $html | Should -Not -BeNullOrEmpty
  }

  It 'generates HTML report with identical VIs (no differences)' -Skip:(-not $script:LabVIEWCLIAvailable) {
    $reportPath = Join-Path $ResultsDir 'labviewcli-comparison-report-nodiff.html'
    
    # Compare VI with itself
  $cliArgs = @(
      '-OperationName', 'CreateComparisonReport',
      '-vi1', $BaseVi,
      '-vi2', $BaseVi,
      '-reportType', 'HTMLSingleFile',
      '-reportPath', $reportPath
    )
    
  & $LabVIEWCLI @cliArgs
    $exitCode = $LASTEXITCODE
    
    # Verify the command executed successfully
    $exitCode | Should -Be 0
    
    # Verify HTML report was created
    Test-Path -LiteralPath $reportPath | Should -BeTrue
    
    # Verify HTML contains content
    $html = Get-Content -LiteralPath $reportPath -Raw
    $html | Should -Not -BeNullOrEmpty
  }

  It 'handles spaces in file paths correctly' -Skip:(-not $script:LabVIEWCLIAvailable) {
    # This test validates that paths with spaces work correctly
    $reportPath = Join-Path $ResultsDir 'labviewcli comparison report with spaces.html'
    
  $cliArgs = @(
      '-OperationName', 'CreateComparisonReport',
      '-vi1', $BaseVi,
      '-vi2', $HeadVi,
      '-reportType', 'HTMLSingleFile',
      '-reportPath', $reportPath
    )
    
  & $LabVIEWCLI @cliArgs
    $exitCode = $LASTEXITCODE
    
    # Verify the command executed successfully
    $exitCode | Should -Be 0
    
    # Verify HTML report was created with the exact name (including spaces)
    Test-Path -LiteralPath $reportPath | Should -BeTrue
  }
}

