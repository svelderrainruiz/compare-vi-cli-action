#Requires -Version 7.0
# Pester v5 tests for Invoke-PesterTests.ps1 dispatcher

# Availability probe function (avoids discovery-time script variable lookups under StrictMode)
$script:_pesterAvailableMemo = $null
function Test-PesterAvailable {
  if ($script:_pesterAvailableMemo -ne $null) { return $script:_pesterAvailableMemo }
  $available = ($null -ne (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge '5.0.0' }))
  $script:_pesterAvailableMemo = $available
  return $available
}

BeforeAll {
  $here = Split-Path -Parent $PSCommandPath
  $root = Resolve-Path (Join-Path $here '..')
  $dispatcherPath = Join-Path $root 'Invoke-PesterTests.ps1'
  
  # Create a test workspace
  $script:testWorkspace = Join-Path $TestDrive 'dispatcher-test-workspace'
  New-Item -ItemType Directory -Path $script:testWorkspace -Force | Out-Null

  # Defensive: Some Pester host scenarios have surfaced an unexpected null $TestDrive late in the file.
  # Provide a resilient fallback to avoid spurious Path binding failures in integration emission tests.
  if (-not $TestDrive) {
    $fallback = Join-Path ([IO.Path]::GetTempPath()) ("pester-fallback-" + [guid]::NewGuid())
    try { New-Item -ItemType Directory -Force -Path $fallback | Out-Null } catch {}
    Set-Variable -Name TestDrive -Value $fallback -Scope Global -Force
  }
}

Describe 'Invoke-PesterTests.ps1 Dispatcher' -Tag 'Unit' {
  
  BeforeEach {
    # Clean up test workspace
    if (Test-Path $script:testWorkspace) {
      Remove-Item -Path $script:testWorkspace -Recurse -Force
    }
    New-Item -ItemType Directory -Path $script:testWorkspace -Force | Out-Null
  }

  Context 'Parameter validation' {
    
    It 'accepts default parameters' {
      # Create minimal test structure
      $testsDir = Join-Path $script:testWorkspace 'tests'
      New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
      
      # Create a minimal test file
      $testFile = Join-Path $testsDir 'Sample.Tests.ps1'
      @'
Describe 'Sample' {
  It 'passes' {
    $true | Should -Be $true
  }
}
'@ | Set-Content -Path $testFile
      
      # Mock Pester availability
      Mock -CommandName Get-Module -MockWith {
        [PSCustomObject]@{
          Name = 'Pester'
          Version = [Version]'5.4.0'
        }
      } -ParameterFilter { $Name -eq 'Pester' -and $ListAvailable }
      
      # The dispatcher should accept default parameters
      # We test this by dot-sourcing and checking parameter defaults
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'TestsPath = ''tests'''
      $scriptContent | Should -Match 'IncludeIntegration = ''false'''
      $scriptContent | Should -Match 'ResultsPath = ''tests/results'''
    }
    
    It 'accepts custom TestsPath parameter' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[string\]\$TestsPath'
    }
    
    It 'accepts custom IncludeIntegration parameter' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[string\]\$IncludeIntegration'
    }
    
    It 'accepts custom ResultsPath parameter' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[string\]\$ResultsPath'
    }

    It 'accepts custom JsonSummaryPath parameter' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[string\]\$JsonSummaryPath'
      $scriptContent | Should -Match 'JSON Summary File'
    }
  }

  Context 'Path resolution' {
    
    It 'resolves relative TestsPath from script root' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$root = \$PSScriptRoot'
      $scriptContent | Should -Match '\$testsDir = Join-Path \$root \$TestsPath'
    }
    
    It 'resolves relative ResultsPath from script root' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$resultsDir = Join-Path \$root \$ResultsPath'
    }
    
    It 'validates tests directory exists' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Test-Path -LiteralPath \$testsDir -PathType Container'
      $scriptContent | Should -Match 'Write-Error "Tests directory not found'
    }
    
    It 'creates results directory if it does not exist' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'New-Item -ItemType Directory -Force -Path \$resultsDir'
    }
  }

  Context 'Pester availability check' {
    
    It 'checks for Pester v5+ availability' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Get-Module -ListAvailable -Name Pester'
      $scriptContent | Should -Match '\$_.Version -ge ''5\.0\.0'''
    }
    
    It 'provides helpful error message when Pester not found' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Pester v5\+ not found'
      $scriptContent | Should -Match 'Install-Module -Name Pester -MinimumVersion 5\.0\.0'
    }
    
    It 'imports Pester with minimum version' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Import-Module Pester -MinimumVersion 5\.0\.0'
    }
  }

  Context 'IncludeIntegration parameter handling' {
    
    It 'handles string "true" value' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$IncludeIntegration -ieq ''true'''
    }
    
    It 'handles boolean value' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'if \(\$IncludeIntegration -is \[string\]\)'
      $scriptContent | Should -Match 'elseif \(\$IncludeIntegration -is \[bool\]\)'
    }
    
    It 'excludes Integration tag when false' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$conf\.Filter\.ExcludeTag = @\(''Integration''\)'
    }
    
    It 'provides clear output about Integration test inclusion' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Excluding Integration-tagged tests'
      $scriptContent | Should -Match 'Including Integration-tagged tests'
    }
  }

  Context 'Pester configuration' {
    
    It 'configures Pester to use detailed verbosity' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$conf\.Output\.Verbosity = ''Detailed'''
    }
    
    It 'enables test result output' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$conf\.TestResult\.Enabled = \$true'
    }
    
    It 'configures NUnitXml output format' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$conf\.TestResult\.OutputFormat = ''NUnitXml'''
    }
    
    It 'sets output path to pester-results.xml' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$conf\.TestResult\.OutputPath = ''pester-results\.xml'''
    }
    
    It 'runs Pester from results directory' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Push-Location -LiteralPath \$resultsDir'
      $scriptContent | Should -Match 'Invoke-Pester -Configuration \$conf'
      $scriptContent | Should -Match 'Pop-Location'
    }
  }

  Context 'Result parsing and summary' {
    
    It 'parses NUnit XML results' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[xml\]\$doc = Get-Content -LiteralPath \$xmlPath'
      $scriptContent | Should -Match '\$rootNode = \$doc\.''test-results'''
    }
    
    It 'extracts test metrics from XML' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\[int\]\$total = \$rootNode\.total'
      $scriptContent | Should -Match '\[int\]\$failed = \$rootNode\.failures'
      $scriptContent | Should -Match '\[int\]\$errors = \$rootNode\.errors'
      $scriptContent | Should -Match '\[int\]\$skipped = \$rootNode\.''not-run'''
    }
    
    It 'calculates passed count' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$passed = \$total - \$failed - \$errors'
    }
    
    It 'generates formatted summary' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '=== Pester Test Summary ==='
      $scriptContent | Should -Match 'Total Tests: \$total'
      $scriptContent | Should -Match 'Passed: \$passed'
      $scriptContent | Should -Match 'Failed: \$failed'
      $scriptContent | Should -Match 'Errors: \$errors'
      $scriptContent | Should -Match 'Skipped: \$skipped'
    }
    
    It 'writes summary to file' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'pester-summary\.txt'
      $scriptContent | Should -Match 'Out-File'
    }

    It 'writes JSON summary to custom file when specified' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$JsonSummaryPath = '\''pester-summary.json'\'''
      $scriptContent | Should -Match 'JSON summary written to:'
      $scriptContent | Should -Match 'ConvertTo-Json'
    }
  }

  Context 'Exit code handling' {
    
    It 'exits with code 1 when tests fail' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'if \(\$failed -gt 0 -or \$errors -gt 0\)'
      $scriptContent | Should -Match 'exit 1'
    }
    
    It 'exits with code 0 when all tests pass' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '✅ All tests passed!'
      $scriptContent | Should -Match 'exit 0'
    }
    
    It 'provides clear error message on test failure' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Tests failed:.*failure.*error'
    }
  }

  Context 'Failure JSON emission' {
    It 'emits pester-failures.json when a test fails' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'pester-failures.json'
      $scriptContent | Should -Match 'Failures JSON written to:'
      $scriptContent | Should -Match '\$failArray \| ConvertTo-Json'
    }
    
    It 'has Write-FailureDiagnostics helper function' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'function Write-FailureDiagnostics'
      $scriptContent | Should -Match 'Write-FailureDiagnostics -PesterResult'
    }
  }

  Context 'Error handling' {
    
    It 'exits with code 1 when tests directory not found' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Error "Tests directory not found'
      $scriptContent | Should -Match 'exit 1'
    }
    
    It 'exits with code 1 when Pester not found' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Error "Pester v5\+ not found'
      $scriptContent | Should -Match 'exit 1'
    }
    
    It 'creates placeholder results XML when results file missing' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      # Dispatcher now writes a warning and synthesizes minimal placeholder XML instead of exiting
      $scriptContent | Should -Match 'Write-Warning "Pester result XML not found; creating minimal placeholder for tooling continuity\."'
      $scriptContent | Should -Match 'Set-Content -LiteralPath \$xmlPath -Value \$placeholder -Encoding UTF8'
      # Also validate fallback error handling path if placeholder creation fails
      $scriptContent | Should -Match 'Write-Error "Failed to create placeholder XML:'
    }
    
    It 'uses try-finally to ensure Pop-Location' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'try \{'
      $scriptContent | Should -Match '\} finally \{'
      $scriptContent | Should -Match 'Pop-Location'
    }
  }

  Context 'Output and logging' {
    
    It 'displays dispatcher header' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Host "=== Pester Test Dispatcher ==="'
    }
    
    It 'displays input parameters' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Host.*Tests Path:.*\$TestsPath'
      $scriptContent | Should -Match 'Write-Host.*Include Integration:.*\$IncludeIntegration'
      $scriptContent | Should -Match 'Write-Host.*Results Path:.*\$ResultsPath'
    }
    
    It 'displays Pester version' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Host.*Using Pester'
    }
    
    It 'displays test execution message' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Write-Host "Executing Pester tests\.\.\."'
    }
  }

  Context 'Script metadata' {
    
    It 'requires PowerShell 7.0' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '#Requires -Version 7\.0'
    }
    
    It 'sets strict mode' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match 'Set-StrictMode -Version Latest'
    }
    
    It 'sets error action preference to Stop' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\$ErrorActionPreference = ''Stop'''
    }
    
    It 'has proper synopsis documentation' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\.SYNOPSIS'
      $scriptContent | Should -Match 'Pester test dispatcher'
    }
    
    It 'has proper description documentation' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\.DESCRIPTION'
      $scriptContent | Should -Match 'pester-selfhosted\.yml workflow'
    }
    
    It 'documents all parameters' {
      $scriptContent = Get-Content $dispatcherPath -Raw
      $scriptContent | Should -Match '\.PARAMETER TestsPath'
      $scriptContent | Should -Match '\.PARAMETER IncludeIntegration'
      $scriptContent | Should -Match '\.PARAMETER ResultsPath'
    }
  }
}

# Integration tests are only defined if Pester v5+ is actually available.
if (Test-PesterAvailable) {
  Describe 'Invoke-PesterTests.ps1 Integration' -Tag 'Integration' {
    BeforeAll {
      # Defensive fallback for $TestDrive (rare null condition seen under filtered tag runs)
      if (-not $TestDrive) {
        $fallback = Join-Path ([IO.Path]::GetTempPath()) ("pester-int-fallback-" + [guid]::NewGuid())
        try { New-Item -ItemType Directory -Force -Path $fallback | Out-Null } catch {}
        Set-Variable -Name TestDrive -Value $fallback -Scope Global -Force
      }
    }

    It 'executes successfully with valid parameters' {
      # Create test workspace
      $workspace = Join-Path $TestDrive 'integration-test'
      New-Item -ItemType Directory -Path $workspace -Force | Out-Null

      $testsDir = Join-Path $workspace 'tests'
      New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

      # Create a simple passing test file consumed by the dispatcher
      $testFile = Join-Path $testsDir 'Simple.Tests.ps1'
      @'
Describe 'Simple Test' {
  It 'should pass' {
    1 + 1 | Should -Be 2
  }
}
'@ | Set-Content -Path $testFile

      # Copy dispatcher to isolated workspace
      $dispatcherCopy = Join-Path $workspace 'Invoke-PesterTests.ps1'
      Copy-Item -Path $dispatcherPath -Destination $dispatcherCopy

      # Execute dispatcher (unit style run - integration off for speed here)
      $resultsPath = Join-Path $workspace 'results'
      & $dispatcherCopy -TestsPath 'tests' -IncludeIntegration 'false' -ResultsPath 'results' 2>&1 | Out-Null

      # Verify result artifacts
      $LASTEXITCODE | Should -Be 0
      Test-Path (Join-Path $resultsPath 'pester-results.xml') | Should -BeTrue
      Test-Path (Join-Path $resultsPath 'pester-summary.txt') | Should -BeTrue
      Test-Path (Join-Path $resultsPath 'pester-summary.json') | Should -BeTrue
    }

    It 'generates manifest with required structure' {
      # Create test workspace
      $workspace = Join-Path $TestDrive 'manifest-test'
      New-Item -ItemType Directory -Path $workspace -Force | Out-Null

      $testsDir = Join-Path $workspace 'tests'
      New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

      # Create a simple passing test consumed by dispatcher
      $testFile = Join-Path $testsDir 'Pass.Tests.ps1'
      @'
Describe 'Passing Test' {
  It 'passes' {
    $true | Should -Be $true
  }
}
'@ | Set-Content -Path $testFile

      # Copy dispatcher
      $dispatcherCopy = Join-Path $workspace 'Invoke-PesterTests.ps1'
      Copy-Item -Path $dispatcherPath -Destination $dispatcherCopy

      # Execute dispatcher with failure artifact emission always on
      $resultsPath = Join-Path $workspace 'results'
      $null = & $dispatcherCopy -TestsPath 'tests' -IncludeIntegration 'false' -ResultsPath 'results' -EmitFailuresJsonAlways 2>&1

      # Verify manifest exists
      $manifestPath = Join-Path $resultsPath 'pester-artifacts.json'
      Test-Path $manifestPath | Should -BeTrue

      # Parse manifest
      $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

      # Verify required fields
      $manifest.manifestVersion | Should -Not -BeNullOrEmpty
      $manifest.generatedAt | Should -Not -BeNullOrEmpty
      $manifest.artifacts | Should -Not -BeNullOrEmpty

      # Verify minimum artifact entries
      $manifest.artifacts.Count | Should -BeGreaterOrEqual 3
      $artifactFiles = $manifest.artifacts | Select-Object -ExpandProperty file
      $artifactFiles | Should -Contain 'pester-results.xml'
      $artifactFiles | Should -Contain 'pester-summary.txt'
      $artifactFiles | Should -Contain 'pester-summary.json'

      # Verify JSON summary has schemaVersion
      $jsonSummary = $manifest.artifacts | Where-Object { $_.file -eq 'pester-summary.json' }
      $jsonSummary.schemaVersion | Should -Not -BeNullOrEmpty
    }
  }
}
else {
  Describe 'Invoke-PesterTests.ps1 Integration (Skipped - Pester Missing)' -Tag 'Integration' {
    It 'skips because Pester v5+ not available' {
      Set-ItResult -Skipped -Because 'Pester v5+ not available'
    }
  }
}
