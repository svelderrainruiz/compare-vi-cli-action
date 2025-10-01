@{
RootModule        = 'CompareLoop.psm1'
ModuleVersion     = '0.1.0'
GUID              = '1fd6c3a9-6f19-4c1b-9c3a-5f9c4dcdb111'
Author            = 'compare-vi-cli-action'
CompanyName       = 'LabVIEW Community'
Copyright         = '(c) 2025 LabVIEW Community'
Description       = 'Loop-oriented LVCompare integration utilities (developer/testing scaffold)'
PowerShellVersion = '5.1'
FunctionsToExport = @('Invoke-IntegrationCompareLoop','Test-CanonicalCli','Format-LoopDuration')
CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @()
PrivateData       = @{ Tags = @('LabVIEW','LVCompare','Diff','Loop'); LicenseUri='https://github.com/LabVIEW-Community-CI-CD/compare-vi-cli-action/blob/main/LICENSE' }
}