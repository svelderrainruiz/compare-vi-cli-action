Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Fixture manifest enforcement' -Tag 'Unit' {
  BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..') | Select-Object -ExpandProperty Path
    $script:validator = Join-Path $repoRoot 'tools' 'Validate-Fixtures.ps1'
    $script:manifest = Join-Path $repoRoot 'fixtures.manifest.json'
    $script:vi1 = Join-Path $repoRoot 'VI1.vi'
  }

  It 'passes with current manifest' {
    $code = pwsh -NoLogo -NoProfile -File $validator | Out-Null; $LASTEXITCODE
    $LASTEXITCODE | Should -Be 0
  }

  It 'detects hash mismatch without token' {
    $original = Get-Content -LiteralPath $vi1 -Raw
    try {
      Add-Content -LiteralPath $vi1 -Value 'x' -Encoding utf8
      pwsh -NoLogo -NoProfile -File $validator | Out-Null
      $LASTEXITCODE | Should -Be 6
    } finally {
      Set-Content -LiteralPath $vi1 -Value $original -Encoding utf8
    }
  }
}
