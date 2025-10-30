function Get-ReportFixtureCases {
    param()

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $fixturesRoot = Join-Path $repoRoot 'fixtures'
    $reportRoot = Join-Path $fixturesRoot 'vi-report'

    if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
        throw "Report fixtures directory not found: $reportRoot"
    }

    $cases = @(
        [ordered]@{
            Name        = 'vi-attribute'
            FixtureRoot = Join-Path $reportRoot 'vi-attribute'
            Headings    = @(
                'VI Attribute - Window Size/Appearance'
                'VI Attribute - Miscellaneous'
            )
            Expected    = @(
                [pscustomobject]@{ slug = 'attributes'; classification = 'signal' }
            )
        }
        [ordered]@{
            Name        = 'block-diagram'
            FixtureRoot = Join-Path $reportRoot 'block-diagram'
            Headings    = @(
                'Block Diagram - Structures'
                'Block Diagram Cosmetic - Frame Objects'
            )
            Expected    = @(
                [pscustomobject]@{ slug = 'block-diagram'; classification = 'signal' }
                [pscustomobject]@{ slug = 'cosmetic'; classification = 'noise' }
            )
        }
        [ordered]@{
            Name        = 'front-panel'
            FixtureRoot = Join-Path $reportRoot 'front-panel'
            Headings    = @(
                'Control Changes - Numeric Controls'
                'Control Changes - Boolean Controls'
            )
            Expected    = @(
                [pscustomobject]@{ slug = 'front-panel'; classification = 'signal' }
            )
        }
    )

    foreach ($case in $cases) {
        $fixtureRoot = $case['FixtureRoot']
        if (-not (Test-Path -LiteralPath $fixtureRoot -PathType Container)) {
            throw "Fixture root not found: $fixtureRoot"
        }
        $reportPath = Join-Path $fixtureRoot 'compare-report.html'
        if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
            throw "Fixture missing compare-report.html: $reportPath"
        }
        $capturePath = Join-Path $fixtureRoot 'lvcompare-capture.json'
        if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
            throw "Fixture missing lvcompare-capture.json: $capturePath"
        }
    }

    return $cases
}
