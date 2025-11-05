param()

Describe 'configs/labview-targets.json' -Tag 'Unit' {
  It 'only lists 2021 32/64 for applyVipc targets' {
    $configPath = Join-Path $PSScriptRoot '..' 'configs' 'labview-targets.json'
    $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -Depth 10
    $applyTargets = $json.operations.applyVipc
    $applyTargets | Should -Not -BeNullOrEmpty

    $expected = @(
      [pscustomobject]@{ version = 2021; bitness = 32 },
      [pscustomobject]@{ version = 2021; bitness = 64 }
    )

    $applyTargets | Should -HaveCount $expected.Count
    foreach ($target in $expected) {
      $match = $applyTargets | Where-Object { $_.version -eq $target.version -and $_.bitness -eq $target.bitness }
      $match | Should -Not -BeNullOrEmpty
    }
  }
}
