Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'LVCompare flags (report verifications)' -Tag 'Unit' {
  BeforeAll {
    $here = Split-Path -Parent $PSCommandPath
    $root = Resolve-Path (Join-Path $here '..')
    # Load CompareVI and helpers without invoking the real CLI
    Import-Module (Join-Path $root 'scripts' 'CompareVI.psm1') -Force
    $script:verifyScript = (Join-Path $root 'tools' 'Verify-FixtureCompare.ps1')

    # Mock Resolve-Cli inside CompareVI module to avoid canonical path existence checks
    Mock -CommandName Resolve-Cli -ModuleName CompareVI -MockWith { param($Explicit) 'C:\\Program Files\\National Instruments\\Shared\\LabVIEW Compare\\LVCompare.exe' }

    # Simple executor that avoids launching LVCompare
    $script:execZero = { param($cli,$b,$h,$argv) return 0 }

    # Creates base/head files in $TestDrive and returns a hashtable { base, head }
    function New-TestVis {
      $vis = Join-Path $TestDrive ('vis-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $vis -Force | Out-Null
      $base = Join-Path $vis 'base.vi'
      $head = Join-Path $vis 'head.vi'
      Set-Content -LiteralPath $base -Value '' -Encoding utf8
      Set-Content -LiteralPath $head -Value 'x' -Encoding utf8
      @{ base = $base; head = $head }
    }

    # Runs CompareVI with given arg spec, writes exec JSON, returns the parsed exec object
    function Invoke-WithArgs([string]$argSpec) {
      $paths = New-TestVis
      $tmpRoot = Join-Path $TestDrive ('ver-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
      $execPath = Join-Path $tmpRoot 'compare-exec.json'
      $null = Invoke-CompareVI -Base $paths.base -Head $paths.head -LvCompareArgs $argSpec -FailOnDiff:$false -Executor $script:execZero -CompareExecJsonPath $execPath
      if (-not (Test-Path -LiteralPath $execPath)) { throw "compare-exec.json missing at: $execPath" }
      return (Get-Content -LiteralPath $execPath -Raw | ConvertFrom-Json -ErrorAction Stop)
    }
  }

  It 'embeds -noattr in report cli command' {
    $exec = Invoke-WithArgs '-noattr'
    $exec.command | Should -Match '(^|\s)-noattr(\s|$)'
  }

  It 'embeds -nofp in report cli command' {
    $exec = Invoke-WithArgs '-nofp'
    $exec.command | Should -Match '(^|\s)-nofp(\s|$)'
  }

  It 'embeds -nofppos in report cli command' {
    $exec = Invoke-WithArgs '-nofppos'
    $exec.command | Should -Match '(^|\s)-nofppos(\s|$)'
  }

  It 'embeds -nobd in report cli command' {
    $exec = Invoke-WithArgs '-nobd'
    $exec.command | Should -Match '(^|\s)-nobd(\s|$)'
  }

  It 'embeds -nobdcosm in report cli command' {
    $exec = Invoke-WithArgs '-nobdcosm'
    $exec.command | Should -Match '(^|\s)-nobdcosm(\s|$)'
  }

  It 'embeds -lvpath value in report cli command' {
    $lv = 'C:\\Path With Space\\LabVIEW.exe'
    # Use equals form to avoid quoting complexity in the spec; normalization will split into flag + value
    $exec = Invoke-WithArgs ("-lvpath=$lv")
    $exec.command | Should -Match '(^|\s)-lvpath(\s|$)'
    $exec.command | Should -Match 'LabVIEW.exe'
  }

  It 'records absolute base/head paths and arg list in exec json' {
    $paths = New-TestVis
    $execPath = Join-Path $TestDrive ('abs-' + [guid]::NewGuid().ToString('N') + '.json')
            $capturedArgs = $null
            $executor = { param($cli,$base,$head,$argv) Set-Variable -Name capturedArgs -Value @($argv) -Scope 1; return 0 }

    Push-Location (Split-Path $paths.base -Parent)
    try {
      Invoke-CompareVI -Base 'base.vi' -Head 'head.vi' -LvCompareArgs '-noattr -nofp' -CompareExecJsonPath $execPath -FailOnDiff:$false -Executor $executor | Out-Null
    } finally {
      Pop-Location
    }

    Test-Path -LiteralPath $execPath | Should -BeTrue
    $exec = Get-Content -LiteralPath $execPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $baseAbs = (Resolve-Path -LiteralPath $paths.base).Path
    $headAbs = (Resolve-Path -LiteralPath $paths.head).Path
    $exec.base | Should -Be $baseAbs
    $exec.head | Should -Be $headAbs
    $patternBase = [regex]::Escape($baseAbs)
    $patternHead = [regex]::Escape($headAbs)
    $exec.command | Should -Match $patternBase
    $exec.command | Should -Match $patternHead
    $exec.command | Should -Match '(^|\s)-noattr(\s|$)'
    $exec.command | Should -Match '(^|\s)-nofp(\s|$)'
    @($exec.args) | Should -Be @('-noattr','-nofp')
  }
}
