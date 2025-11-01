Describe 'Summarize-VIStaging.ps1' -Tag 'Unit' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'tools' 'Summarize-VIStaging.ps1'
        $script:originalLocation = Get-Location
        Set-Location $script:repoRoot
    }

    AfterAll {
        if ($script:originalLocation) {
            Set-Location $script:originalLocation
        }
    }

    It 'produces markdown summary for diff pair' {
        $compareRoot = Join-Path $TestDrive 'compare'
        $pairDir = Join-Path $compareRoot 'pair-01'
        New-Item -ItemType Directory -Path $pairDir -Force | Out-Null

        $html = @'
<!DOCTYPE html>
<html>
<body>
<div class="included-attributes">
  <ul class="inclusion-list">
    <li class="checked">Front Panel</li>
    <li class="checked">Block Diagram Functional</li>
    <li class="unchecked">Block Diagram Cosmetic</li>
    <li class="checked">VI Attribute</li>
  </ul>
</div>
<details open>
  <summary class="difference-heading">1. VI Attribute - Miscellaneous</summary>
  <ol class="detailed-description-list">
    <li class="diff-detail">Difference Type: VI icon</li>
  </ol>
</details>
<details open>
  <summary class="difference-heading">2. Block Diagram Functional - Nodes</summary>
</details>
</body>
</html>
'@
        $reportPath = Join-Path $pairDir 'compare-report.html'
        $html | Set-Content -LiteralPath $reportPath -Encoding utf8

        $compareEntry = @(
            [ordered]@{
                index      = 1
                changeType = 'modify'
                basePath   = 'VI1.vi'
                headPath   = 'VI1.vi'
                stagedBase = 'staged\Base.vi'
                stagedHead = 'staged\Head.vi'
                status     = 'diff'
                exitCode   = 1
                outputDir  = $pairDir
                reportPath = $reportPath
            }
        )

        $compareJson = Join-Path $TestDrive 'vi-staging-compare.json'
        $compareEntry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $compareJson -Encoding utf8

        $mdPath = Join-Path $TestDrive 'summary.md'
        $jsonPath = Join-Path $TestDrive 'summary.json'

        $result = & $script:scriptPath -CompareJson $compareJson -MarkdownPath $mdPath -SummaryJsonPath $jsonPath

        $result | Should -Not -BeNullOrEmpty
        $result.pairs.Count | Should -Be 1
        $result.pairs[0].diffCategories | Should -Contain 'VI Attribute'
        $result.pairs[0].diffCategories | Should -Contain 'Block Diagram Functional'
        $result.pairs[0].diffCategoryDetails | Should -Not -BeNullOrEmpty
        ($result.pairs[0].diffCategoryDetails | Where-Object { $_.slug -eq 'vi-attribute' }).Count | Should -Be 1
        ($result.pairs[0].diffCategoryDetails | Where-Object { $_.slug -eq 'block-diagram-functional' }).Count | Should -Be 1
        $result.pairs[0].diffBuckets | Should -Contain 'metadata'
        $result.pairs[0].diffBuckets | Should -Contain 'functional-behavior'
        ($result.pairs[0].diffBucketDetails | Where-Object { $_.slug -eq 'metadata' }).Count | Should -Be 1
        ($result.pairs[0].diffBucketDetails | Where-Object { $_.slug -eq 'functional-behavior' }).Count | Should -Be 1
        $result.pairs[0].includedAttributes.Count | Should -BeGreaterThan 0
        ($result.pairs[0].includedAttributes | Where-Object { $_.name -eq 'VI Attribute' }).value | Should -BeTrue
        (@($result.pairs[0].diffDetailPreview | Where-Object { $_ -match 'Difference Type: VI icon' })).Count | Should -BeGreaterThan 0
        $result.pairs[0].stagedBase | Should -Be 'staged\Base.vi'
        $result.pairs[0].stagedHead | Should -Be 'staged\Head.vi'
        $result.pairs[0].flagSummary | Should -Be '_none_'

        Test-Path -LiteralPath $mdPath | Should -BeTrue
        $markdown = Get-Content -LiteralPath $mdPath -Raw
        $markdown | Should -Match '\| Pair \| Status \| Diff Categories \| Included \| Report \| Flags \| Leak \|'
        $markdown | Should -Match 'VI Attribute'
        $markdown | Should -Match 'Difference Type: VI icon'
        $markdown | Should -Match 'Buckets:'
        $markdown | Should -Match 'Functional behavior'
        $markdown | Should -Match 'Metadata'

        Test-Path -LiteralPath $jsonPath | Should -BeTrue
        $jsonPayload = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json -Depth 6
        $jsonPayload.totals.diff | Should -Be 1
        (@($jsonPayload.pairs[0].diffDetailPreview | Where-Object { $_ -match 'Difference Type: VI icon' })).Count | Should -BeGreaterThan 0
        $jsonPayload.pairs[0].diffCategoryDetails | Should -Not -BeNullOrEmpty
        $jsonPayload.totals.categoryCounts.'vi-attribute' | Should -Be 1
        $jsonPayload.totals.categoryCounts.'block-diagram-functional' | Should -Be 1
        $jsonPayload.totals.bucketCounts.'metadata' | Should -Be 1
        $jsonPayload.totals.bucketCounts.'functional-behavior' | Should -Be 1
        $jsonPayload.pairs[0].flagSummary | Should -Be '_none_'
    }

    It 'resolves report path when compare summary omits metadata' {
        $compareRoot = Join-Path $TestDrive 'compare'
        $pairDir = Join-Path $compareRoot 'pair-01'
        New-Item -ItemType Directory -Path $pairDir -Force | Out-Null

        $html = @'
<!DOCTYPE html>
<html>
<body>
<details open>
  <summary class="difference-heading">1. Block Diagram Functional - Nodes</summary>
  <ol class="detailed-description-list">
    <li class="diff-detail">Node changed</li>
  </ol>
</details>
</body>
</html>
'@
        $reportPath = Join-Path $pairDir 'compare-report.html'
        $html | Set-Content -LiteralPath $reportPath -Encoding utf8

        $capturePayload = @{ exitCode = 1 } | ConvertTo-Json
        $capturePayload | Set-Content -LiteralPath (Join-Path $pairDir 'lvcompare-capture.json') -Encoding utf8

        $compareEntry = @(
            [ordered]@{
                index      = 1
                changeType = 'modify'
                basePath   = 'VI1.vi'
                headPath   = 'VI1.vi'
                outputDir  = $pairDir
                status     = 'diff'
                exitCode   = 1
                reportPath = $null
                capturePath= $null
            }
        )

        $compareJson = Join-Path $TestDrive 'vi-staging-compare-missing.json'
        $compareEntry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $compareJson -Encoding utf8

        $result = & $script:scriptPath -CompareJson $compareJson

        $result | Should -Not -BeNullOrEmpty
        $result.pairs.Count | Should -Be 1
        ($result.pairs[0].reportRelative.Replace('\','/')) | Should -Be 'pair-01/compare-report.html'
        $result.pairs[0].diffCategories | Should -Contain 'Block Diagram Functional'
        $result.pairs[0].diffCategoryDetails[0].slug | Should -Be 'block-diagram-functional'
    }

    It 'handles missing report gracefully' {
        $compareEntry = @(
            [ordered]@{
                index      = 2
                changeType = 'modify'
                basePath   = 'VI2.vi'
                headPath   = 'VI2.vi'
                status     = 'skipped'
                exitCode   = $null
                outputDir  = (Join-Path $TestDrive 'missing')
            }
        )

        $compareJson = Join-Path $TestDrive 'vi-staging-compare-empty.json'
        $compareEntry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $compareJson -Encoding utf8

        $result = & $script:scriptPath -CompareJson $compareJson

        $result.pairs.Count | Should -Be 1
        $result.pairs[0].status | Should -Be 'skipped'
        $result.pairs[0].diffCategories.Count | Should -Be 0
        $result.pairs[0].diffCategoryDetails.Count | Should -Be 0
        $result.pairs[0].diffBuckets.Count | Should -Be 0
        $result.pairs[0].diffBucketDetails.Count | Should -Be 0
        $result.markdown | Should -Match 'Totals'
    }

    It 'tracks leak warnings in totals and markdown' {
        $compareRoot = Join-Path $TestDrive 'compare'
        $pairDir = Join-Path $compareRoot 'pair-01'
        New-Item -ItemType Directory -Path $pairDir -Force | Out-Null

        $compareEntry = @(
            [ordered]@{
                index          = 1
                changeType     = 'modify'
                basePath       = 'VI1.vi'
                headPath       = 'VI1.vi'
                status         = 'diff'
                exitCode       = 1
                outputDir      = $pairDir
                reportPath     = $null
                leakWarning    = $true
                leakLvcompare  = 3
                leakLabVIEW    = 1
                leakPath       = Join-Path $pairDir 'compare-leak.json'
            }
        )

        $compareJson = Join-Path $TestDrive 'vi-staging-compare-leak.json'
        $compareEntry | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $compareJson -Encoding utf8

        $result = & $script:scriptPath -CompareJson $compareJson

        $result | Should -Not -BeNullOrEmpty
        $result.totals.leakWarnings | Should -Be 1
        $result.pairs.Count | Should -Be 1
        $result.pairs[0].leakWarning | Should -BeTrue
        $result.pairs[0].leakLvcompare | Should -Be 3
        $result.pairs[0].leakLabVIEW | Should -Be 1
        $result.markdown.Contains('lv=3') | Should -BeTrue
        $result.markdown.Contains('lab=1') | Should -BeTrue
        $result.markdown | Should -Match 'Totals'
    }
}
