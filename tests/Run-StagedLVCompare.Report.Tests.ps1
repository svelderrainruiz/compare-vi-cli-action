. (Join-Path $PSScriptRoot 'ReportFixtureHelpers.ps1')
$ReportFixtureCases = Get-ReportFixtureCases

Describe "Report fixtures" {
  It "contains expected sections for <Name>" -TestCases $ReportFixtureCases {
    param($Name, $FixtureRoot, $Headings)

    Test-Path -LiteralPath $FixtureRoot | Should -BeTrue

    $capturePath = Join-Path $FixtureRoot 'lvcompare-capture.json'
    $capture = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json -Depth 4
    $capture.schema | Should -Be 'lvcompare-capture-v1'
    $capture.cli.reportPath | Should -Be './compare-report.html'
    $capture.out.reportHtml | Should -Be './compare-report.html'

    $reportPath = Join-Path $FixtureRoot 'compare-report.html'
    $html = Get-Content -LiteralPath $reportPath -Raw
    $html | Should -Match 'LabVIEW VI Comparison Report'

    foreach ($heading in $Headings) {
      $html | Should -Match ([regex]::Escape($heading))
    }
  }
}
