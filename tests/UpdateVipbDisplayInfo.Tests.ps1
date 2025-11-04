#Requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'Update-VipbDisplayInfo.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:ScriptPath = Join-Path $RepoRoot '.github\actions\modify-vipb-display-info\Update-VipbDisplayInfo.ps1'
        $script:FixtureVipb = Join-Path $RepoRoot '.github\actions\build-vi-package\NI Icon editor.vipb'

        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            throw "Update-VipbDisplayInfo.ps1 not found at '$ScriptPath'."
        }

        $originalDoc = New-Object System.Xml.XmlDocument
        $originalDoc.PreserveWhitespace = $true
        $originalDoc.Load($FixtureVipb)
        $script:OriginalXml = $originalDoc
    }

    It 'updates only the targeted display nodes' {
        $vipbCopyDir = Join-Path $TestDrive 'vipb'
        New-Item -ItemType Directory -Path $vipbCopyDir | Out-Null

        $vipbCopyPath = Join-Path $vipbCopyDir 'spec-under-test.vipb'
        Copy-Item -LiteralPath $FixtureVipb -Destination $vipbCopyPath -Force

        $releaseNotesRelative = 'release_notes.md'
        $displayPayload = @{
            'Package Version' = @{
                major = 9
                minor = 8
                patch = 7
                build = 6
            }
            'Product Name'                   = 'Injected Product'
            'Company Name'                   = 'Injected Co'
            'Author Name (Person or Company)'= 'Injected Author'
            'Product Description Summary'    = 'Summary text'
            'Product Description'            = 'Full description'
            'Release Notes - Change Log'     = 'Release notes text'
            'Product Homepage (URL)'         = 'https://example.test'
            'Legal Copyright'                = 'Copyright 2025'
            'License Agreement Name'         = 'Custom License'
        } | ConvertTo-Json -Depth 5

        & $ScriptPath `
            -MinimumSupportedLVVersion 2023 `
            -LabVIEWMinorRevision 3 `
            -SupportedBitness 64 `
            -Major 9 `
            -Minor 8 `
            -Patch 7 `
            -Build 6 `
            -Commit 'commit-hash' `
            -RelativePath $vipbCopyDir `
            -VIPBPath (Split-Path -Leaf $vipbCopyPath) `
            -ReleaseNotesFile $releaseNotesRelative `
            -DisplayInformationJSON $displayPayload

        $updatedDoc = New-Object System.Xml.XmlDocument
        $updatedDoc.PreserveWhitespace = $true
        $updatedDoc.Load($vipbCopyPath)

        $updatedRoot = $updatedDoc.VI_Package_Builder_Settings

        $updatedRoot.Library_General_Settings.Company_Name | Should -Be 'INJECTED CO'
        $updatedRoot.Library_General_Settings.Product_Name | Should -Be 'Injected Product'
        $updatedRoot.Library_General_Settings.Library_Summary | Should -Be 'Summary text'
        $updatedRoot.Library_General_Settings.Library_License | Should -Be 'Custom License'
        $updatedRoot.Library_General_Settings.Library_Version | Should -Be '9.8.7.6'
        $updatedRoot.Library_General_Settings.Package_LabVIEW_Version | Should -Be '23.3 (64-bit)'

        $desc = $updatedRoot.Advanced_Settings.Description
        $desc.One_Line_Description_Summary | Should -Be 'Summary text'
        $desc.Description | Should -Be 'Full description'
        $desc.Release_Notes | Should -Be 'Release notes text'
        $desc.Packager | Should -Be 'INJECTED AUTHOR'
        $desc.URL | Should -Be 'https://example.test'
        $desc.Copyright | Should -Be 'Copyright 2025'

        $updatedRoot.Advanced_Settings.VI_Package_Configuration_File | Should -Be 'spec-under-test.vipc'

        $updatedRoot.GetAttribute('ID') | Should -Not -Be $OriginalXml.VI_Package_Builder_Settings.GetAttribute('ID')
        $updatedRoot.GetAttribute('Modified_Date') | Should -Not -Be $OriginalXml.VI_Package_Builder_Settings.GetAttribute('Modified_Date')

        Test-Path (Join-Path $vipbCopyDir $releaseNotesRelative) | Should -BeTrue

        function Reset-NodeValue {
            param(
                [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
                [Parameter(Mandatory)][System.Xml.XmlDocument]$Baseline,
                [Parameter(Mandatory)][string]$XPath
            )
            $baselineNode = $Baseline.SelectSingleNode($XPath)
            $target = $Document.SelectSingleNode($XPath)
            if (-not $baselineNode -or -not $target) { return }

            $parent = $target.ParentNode
            if (-not $parent) { return }

            $imported = $Document.ImportNode($baselineNode, $true)
            $parent.ReplaceChild($imported, $target) | Out-Null
        }

        $sanitized = New-Object System.Xml.XmlDocument
        $sanitized.PreserveWhitespace = $true
        $sanitized.LoadXml($updatedDoc.OuterXml)

        $pathsToRestore = @(
            '/VI_Package_Builder_Settings/Library_General_Settings/Product_Name',
            '/VI_Package_Builder_Settings/Library_General_Settings/Company_Name',
            '/VI_Package_Builder_Settings/Library_General_Settings/Library_Summary',
            '/VI_Package_Builder_Settings/Library_General_Settings/Library_License',
            '/VI_Package_Builder_Settings/Library_General_Settings/Library_Version',
            '/VI_Package_Builder_Settings/Library_General_Settings/Package_LabVIEW_Version',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/One_Line_Description_Summary',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/Description',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/Release_Notes',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/Packager',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/URL',
            '/VI_Package_Builder_Settings/Advanced_Settings/Description/Copyright',
            '/VI_Package_Builder_Settings/Advanced_Settings/VI_Package_Configuration_File'
        )

        foreach ($path in $pathsToRestore) {
            Reset-NodeValue -Document $sanitized -Baseline $OriginalXml -XPath $path
        }

        $sanitized.DocumentElement.SetAttribute('ID', $OriginalXml.DocumentElement.GetAttribute('ID'))
        $sanitized.DocumentElement.SetAttribute('Modified_Date', $OriginalXml.DocumentElement.GetAttribute('Modified_Date'))

        $sanitized.OuterXml | Should -Be $OriginalXml.OuterXml
    }
}
