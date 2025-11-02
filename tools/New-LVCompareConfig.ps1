#Requires -Version 7.0
[CmdletBinding()]
param(
  [string]$OutputPath,
  [switch]$NonInteractive,
  [switch]$Force,
  [switch]$Probe,
  [string]$LabVIEWExePath,
  [string]$LVComparePath,
  [string]$LabVIEWCLIPath,
  [string]$Version,
  [ValidateSet('32','64')]
  [string]$Bitness
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
  throw 'This helper currently targets Windows hosts (LVCompare/LabVIEWCLI).'
}

$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $scriptDir) { throw 'Unable to detect script directory.' }
$repoRoot = Split-Path -Parent $scriptDir
if (-not $repoRoot) { throw 'Unable to determine repository root.' }

$vendorModule = Join-Path $repoRoot 'tools' 'VendorTools.psm1'
if (-not (Test-Path -LiteralPath $vendorModule -PathType Leaf)) {
  throw "VendorTools.psm1 not found at $vendorModule"
}
Import-Module $vendorModule -Force | Out-Null

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Add-CandidateValue {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [System.Collections.Generic.List[string]]$Target,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  foreach ($existing in $Target) {
    if ($existing -and $existing.Equals($Value, [System.StringComparison]::OrdinalIgnoreCase)) {
      return
    }
  }
  $Target.Add($Value)
}

function Try-NormalizePath {
  param([string]$Candidate)
  if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
  $expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim('"'))
  if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) { return $null }
  try {
    return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).Path
  } catch {
    return $expanded
  }
}

function Get-ConfigPropertyValues {
  param([Parameter(Mandatory = $true)][string]$PropertyName)

  $values = [System.Collections.Generic.List[string]]::new()
  foreach ($configName in @('labview-paths.local.json','labview-paths.json')) {
    $configPath = Join-Path $repoRoot 'configs' $configName
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
    try {
      $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -Depth 5
      if ($null -eq $config) { continue }
      $propValue = $config.PSObject.Properties[$PropertyName]
      if ($propValue) {
        $prop = $propValue.Value
        if ($prop -is [string]) {
          Add-CandidateValue -Target $values -Value $prop
        } elseif ($prop -is [System.Collections.IEnumerable] -and -not ($prop -is [string])) {
          foreach ($entry in $prop) {
            if ($entry) { Add-CandidateValue -Target $values -Value ([string]$entry) }
          }
        }
      }

      $versionsProp = $config.PSObject.Properties['versions']
      if ($versionsProp) {
        $versionsNode = $versionsProp.Value
        if ($versionsNode) {
          $versionEntries = @()
          if ($versionsNode -is [System.Collections.IDictionary]) {
            foreach ($key in $versionsNode.Keys) {
              $versionEntries += [pscustomobject]@{ Name = $key; Value = $versionsNode[$key] }
            }
          } else {
            $versionEntries = $versionsNode.PSObject.Properties
          }

          foreach ($versionProp in $versionEntries) {
            $bitnessNode = $versionProp.Value
            if (-not $bitnessNode) { continue }
            $bitnessEntries = @()
            if ($bitnessNode -is [System.Collections.IDictionary]) {
              foreach ($key in $bitnessNode.Keys) {
                $bitnessEntries += [pscustomobject]@{ Name = $key; Value = $bitnessNode[$key] }
              }
            } else {
              $bitnessEntries = $bitnessNode.PSObject.Properties
            }

            foreach ($bitnessProp in $bitnessEntries) {
              $entryObject = $bitnessProp.Value
              if (-not $entryObject) { continue }
              if ($entryObject -is [System.Collections.IDictionary]) {
                if ($entryObject.Contains($PropertyName)) {
                  Add-CandidateValue -Target $values -Value ([string]$entryObject[$PropertyName])
                }
              } else {
                $entryValueProp = $entryObject.PSObject.Properties[$PropertyName]
                if ($entryValueProp -and $entryValueProp.Value) {
                  Add-CandidateValue -Target $values -Value ([string]$entryValueProp.Value)
                }
              }
            }
          }
        }
      }
    } catch {}
  }
  return $values
}

function Get-LVCompareCandidatePaths {
  $candidates = [System.Collections.Generic.List[string]]::new()
  foreach ($entry in (Get-ConfigPropertyValues -PropertyName 'lvcompare')) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }
  foreach ($entry in (Get-ConfigPropertyValues -PropertyName 'LVComparePath')) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

  foreach ($entry in @($env:LVCOMPARE_PATH, $env:LV_COMPARE_PATH)) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

foreach ($entry in @(
      (Join-Path $env:ProgramFiles 'National Instruments\Shared\LabVIEW Compare\LVCompare.exe')
    )) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

  return $candidates
}

function Get-LabVIEWCliCandidatePaths {
  $candidates = [System.Collections.Generic.List[string]]::new()

  foreach ($entry in (Get-ConfigPropertyValues -PropertyName 'labviewcli')) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }
  foreach ($entry in (Get-ConfigPropertyValues -PropertyName 'LabVIEWCLIPath')) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

  foreach ($entry in @($env:LABVIEWCLI_PATH, $env:LABVIEW_CLI_PATH)) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

  foreach ($entry in @(
      (Join-Path $env:ProgramFiles 'National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe')
    )) {
    $normalized = Try-NormalizePath -Candidate $entry
    if ($normalized) { Add-CandidateValue -Target $candidates -Value $normalized }
  }

  return $candidates
}

function Get-VersionMetadataFromPath {
  param([string]$LabVIEWPath)

  if ([string]::IsNullOrWhiteSpace($LabVIEWPath)) { return $null }
  $version = $null
  $normalized = $LabVIEWPath

  if ($normalized -match 'LabVIEW\s+(\d{4}(?:\s*Q\d)?)') {
    $versionCandidate = $matches[1]
    if ($versionCandidate) {
      $version = ($versionCandidate -replace '\s+', '')
    }
  }

  $bitness = $null
  if ($normalized -match '\(32-bit\)') {
    $bitness = '32'
  } elseif ($normalized -match '\(64-bit\)') {
    $bitness = '64'
  } elseif ($normalized -match '(?i)Program Files \(x86\)') {
    $bitness = '32'
  } elseif ($normalized -match '(?i)Program Files') {
    $bitness = '64'
  }

  if (-not $version -and -not $bitness) {
    return $null
  }

  return [pscustomobject]@{
    version = $version
    bitness = $bitness
  }
}

function Convert-VersionNodeToOrdered {
  param($Node)

  if ($null -eq $Node) { return $null }

  if ($Node -is [System.Collections.IDictionary]) {
    $ordered = [ordered]@{}
    foreach ($key in $Node.Keys) {
      $ordered[$key] = Convert-VersionNodeToOrdered $Node[$key]
    }
    return $ordered
  }

  if ($Node -is [pscustomobject]) {
    $ordered = [ordered]@{}
    foreach ($prop in $Node.PSObject.Properties) {
      $ordered[$prop.Name] = Convert-VersionNodeToOrdered $prop.Value
    }
    return $ordered
  }

  if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
    $list = @()
    foreach ($item in $Node) { $list += Convert-VersionNodeToOrdered $item }
    return $list
  }

  return $Node
}

if (-not $OutputPath) {
  $OutputPath = Join-Path $repoRoot 'configs' 'labview-paths.local.json'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $repoRoot $OutputPath
}

$existingConfig = $null
if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
  if (-not $Force) {
  throw "Output file already exists: $OutputPath (pass -Force to overwrite)"
}
  try {
    $existingConfig = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -Depth 8
  } catch {
    Write-Warning ("Failed to parse existing config at {0}: {1}" -f $OutputPath, $_.Exception.Message)
  }
}

function Resolve-ExistingPath {
  param([string]$Candidate)
  if (-not $Candidate) { return $null }
  $expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim('"'))
  if (Test-Path -LiteralPath $expanded -PathType Leaf) {
    return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).Path
  }
  return $expanded
}

$detectedLabVIEWExe = $null
if (-not $LabVIEWExePath) {
  try {
    $labviewCandidates = @(Get-LabVIEWCandidateExePaths)
    if ($labviewCandidates.Count -gt 0) {
      $detectedLabVIEWExe = $labviewCandidates[0]
    }
  } catch {}
} else {
  $detectedLabVIEWExe = Resolve-ExistingPath -Candidate $LabVIEWExePath
}

$labviewCandidatesFull = [System.Collections.Generic.List[string]]::new()
try {
  foreach ($candidate in (Get-LabVIEWCandidateExePaths)) {
    Add-CandidateValue -Target $labviewCandidatesFull -Value $candidate
  }
} catch {}
if ($detectedLabVIEWExe) {
  Add-CandidateValue -Target $labviewCandidatesFull -Value $detectedLabVIEWExe
}

$labviewCandidatesArray = $labviewCandidatesFull.ToArray()
if (-not $LabVIEWExePath -and ($Version -or $Bitness)) {
  $preferredLv = $labviewCandidatesArray
  if ($Version) {
    $preferredLv = @($preferredLv | Where-Object { $_ -match ("LabVIEW\s+$([regex]::Escape($Version))") })
    if ($preferredLv.Count -eq 0) {
      $preferredLv = @($labviewCandidatesArray | Where-Object { $_ -match $Version })
    }
  }
  if ($Bitness -eq '32') {
    $preferredLv = @($preferredLv | Where-Object { $_ -match '(?i)(\(32-bit\)|Program Files \(x86\))' })
    if ($preferredLv.Count -eq 0) {
      $preferredLv = @($labviewCandidatesArray | Where-Object { $_ -match '(?i)(\(32-bit\)|Program Files \(x86\))' })
    }
  } elseif ($Bitness -eq '64') {
    $preferredLv = @($preferredLv | Where-Object { $_ -notmatch '(?i)(\(32-bit\)|Program Files \(x86\))' })
    if ($preferredLv.Count -eq 0) {
      $preferredLv = @($labviewCandidatesArray | Where-Object { $_ -notmatch '(?i)(\(32-bit\)|Program Files \(x86\))' })
    }
  }
  if ($preferredLv.Count -gt 0) {
    $detectedLabVIEWExe = $preferredLv[0]
  }
}

$detectedLVCompare = $null
$lvcompareCandidatesRaw = @(Get-LVCompareCandidatePaths)
$normalizedProvided = $null
if (-not $LVComparePath) {
  if ($lvcompareCandidatesRaw.Count -gt 0) { $detectedLVCompare = $lvcompareCandidatesRaw[0] }
} else {
  $detectedLVCompare = Resolve-ExistingPath -Candidate $LVComparePath
  $normalizedProvided = Try-NormalizePath -Candidate $LVComparePath
}
$lvcompareCandidatesList = [System.Collections.Generic.List[string]]::new()
foreach ($c in $lvcompareCandidatesRaw) { Add-CandidateValue -Target $lvcompareCandidatesList -Value $c }
if ($normalizedProvided) { Add-CandidateValue -Target $lvcompareCandidatesList -Value $normalizedProvided }
if ($detectedLVCompare) { Add-CandidateValue -Target $lvcompareCandidatesList -Value $detectedLVCompare }

$detectedCLI = $null
$cliCandidatesRaw = @(Get-LabVIEWCliCandidatePaths)
if (-not $LabVIEWCLIPath) {
  if ($cliCandidatesRaw.Count -gt 0) { $detectedCLI = $cliCandidatesRaw[0] }
} else {
  $detectedCLI = Resolve-ExistingPath -Candidate $LabVIEWCLIPath
}
$cliPreferred = $cliCandidatesRaw
if ($Bitness -eq '32') {
  $cliPreferred = @($cliPreferred | Where-Object { $_ -match '(?i)Program Files \(x86\)' })
} elseif ($Bitness -eq '64') {
  $cliPreferred = @($cliPreferred | Where-Object { $_ -notmatch '(?i)Program Files \(x86\)' })
}
if (-not $LabVIEWCLIPath) {
  if ($Bitness -eq '32') {
    $cliPreferred = @($cliPreferred | Where-Object { $_ -match '(?i)Program Files \(x86\)' })
  } elseif ($Bitness -eq '64') {
    $cliPreferred = @($cliPreferred | Where-Object { $_ -notmatch '(?i)Program Files \(x86\)' })
  }
  if ($cliPreferred.Count -gt 0) {
    $detectedCLI = $cliPreferred[0]
  }
}
$cliCandidatesList = [System.Collections.Generic.List[string]]::new()
foreach ($c in $cliCandidatesRaw) { Add-CandidateValue -Target $cliCandidatesList -Value $c }
if ($detectedCLI) { Add-CandidateValue -Target $cliCandidatesList -Value $detectedCLI }

function Prompt-ForPath {
  param(
    [string]$Label,
    [string]$Default,
    [string[]]$Candidates
  )

  if ($NonInteractive.IsPresent) {
    if ($Default) { return $Default }
    if ($Candidates) {
      $firstCandidate = @( $Candidates | Where-Object { $_ } | Select-Object -First 1 )
      if ($firstCandidate) { return $firstCandidate[0] }
    }
    return $Default
  }

  Write-Host ''
  Write-Host ("{0} path:" -f $Label) -ForegroundColor Cyan
  $candidateArray = @()
  if ($Candidates) { $candidateArray = @($Candidates | Where-Object { $_ }) }

  if ($candidateArray.Count -gt 0) {
    Write-Host '  Candidates:'
    for ($i = 0; $i -lt $candidateArray.Count; $i++) {
      $marker = ''
      if ($Default -and $candidateArray[$i].Equals($Default, [System.StringComparison]::OrdinalIgnoreCase)) {
        $marker = ' (default)'
      }
      Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $candidateArray[$i], $marker)
    }
  } elseif ($Default) {
    Write-Host ("  Suggested: {0}" -f $Default)
  } else {
    Write-Host '  (no candidate detected)'
  }

  while ($true) {
    $input = Read-Host 'Enter path (blank=suggested, number=choose candidate)'
    if ([string]::IsNullOrWhiteSpace($input)) {
      if ($Default) {
        return $Default
      }
      if ($candidateArray.Count -gt 0) {
        return $candidateArray[0]
      }
      Write-Warning 'No suggestion available; please provide a path.'
      continue
    }

    if ($input -match '^\d+$') {
      $index = [int]$input - 1
      if ($index -ge 0 -and $index -lt $candidateArray.Count) {
        return $candidateArray[$index]
      }
      Write-Warning ("Candidate {0} is out of range." -f $input)
      continue
    }
    $resolved = Resolve-ExistingPath -Candidate $input
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
      Write-Warning ("Path not found: {0}" -f $resolved)
      $confirm = Read-Host 'Use anyway? (y/N)'
      if ($confirm -notin @('y','Y')) { continue }
    }
    return $resolved
  }
}

$labviewCandidatesForPrompt = $labviewCandidatesArray
$lvcompareCandidatesForPrompt = $lvcompareCandidatesList.ToArray()
$cliCandidatesForPrompt = $cliCandidatesList.ToArray()

$labviewPathFinal = Prompt-ForPath -Label 'LabVIEW.exe' -Default $detectedLabVIEWExe -Candidates $labviewCandidatesForPrompt
$lvcomparePathFinal = Prompt-ForPath -Label 'LVCompare.exe' -Default $detectedLVCompare -Candidates $lvcompareCandidatesForPrompt
$labviewCliPathFinal = Prompt-ForPath -Label 'LabVIEWCLI.exe' -Default $detectedCLI -Candidates $cliCandidatesForPrompt

$configObject = [ordered]@{}
if ($existingConfig) {
  foreach ($prop in $existingConfig.PSObject.Properties) {
    if ($prop.Name -eq 'versions') {
      $configObject[$prop.Name] = Convert-VersionNodeToOrdered $prop.Value
    } else {
      $configObject[$prop.Name] = $prop.Value
    }
  }
}

$configObject['LabVIEWExePath'] = $labviewPathFinal
$configObject['LVComparePath']  = $lvcomparePathFinal
$configObject['LabVIEWCLIPath'] = $labviewCliPathFinal

if ($labviewPathFinal) { $configObject['labview'] = @($labviewPathFinal) } elseif ($configObject.Contains('labview')) { $configObject.Remove('labview') }
if ($lvcomparePathFinal) { $configObject['lvcompare'] = @($lvcomparePathFinal) } elseif ($configObject.Contains('lvcompare')) { $configObject.Remove('lvcompare') }
if ($labviewCliPathFinal) { $configObject['labviewcli'] = @($labviewCliPathFinal) } elseif ($configObject.Contains('labviewcli')) { $configObject.Remove('labviewcli') }

$versionsOrdered = $null
if ($configObject.Contains('versions')) {
  $versionsOrdered = $configObject['versions']
}
if (-not $versionsOrdered) { $versionsOrdered = [ordered]@{} }

$autoVersionMeta = Get-VersionMetadataFromPath -LabVIEWPath $labviewPathFinal
$versionKey = $Version
if (-not $versionKey -and $autoVersionMeta) {
  $versionKey = $autoVersionMeta.version
}
$bitnessKey = $Bitness
if (-not $bitnessKey -and $autoVersionMeta -and $autoVersionMeta.bitness) {
  $bitnessKey = $autoVersionMeta.bitness
}
if ($versionKey) {
  if (-not $bitnessKey) { $bitnessKey = '64' }
  if (-not $versionsOrdered.Contains($versionKey)) {
    $versionsOrdered[$versionKey] = [ordered]@{}
  } elseif ($versionsOrdered[$versionKey] -isnot [System.Collections.IDictionary]) {
    $versionsOrdered[$versionKey] = Convert-VersionNodeToOrdered $versionsOrdered[$versionKey]
  }
  $versionNode = $versionsOrdered[$versionKey]
  if ($null -eq $versionNode) { $versionNode = [ordered]@{} }
  $entry = [ordered]@{}
  if ($labviewPathFinal) { $entry.LabVIEWExePath = $labviewPathFinal }
  if ($lvcomparePathFinal) { $entry.LVComparePath  = $lvcomparePathFinal }
  if ($labviewCliPathFinal) { $entry.LabVIEWCLIPath = $labviewCliPathFinal }
  $versionNode[$bitnessKey] = $entry
  $versionsOrdered[$versionKey] = $versionNode
}

if ($versionsOrdered.Count -gt 0) {
  $configObject['versions'] = $versionsOrdered
} elseif ($configObject.Contains('versions')) {
  $configObject.Remove('versions')
}

$outputDir = Split-Path -Parent $OutputPath
if ($outputDir) { Ensure-Directory -Path $outputDir }

$configObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host ''
Write-Host 'LVCompare config written to:' -ForegroundColor Green
Write-Host ("  {0}" -f $OutputPath)

if ($Probe.IsPresent) {
  $probeScript = Join-Path $repoRoot 'tools' 'Verify-LVCompareSetup.ps1'
  if (Test-Path -LiteralPath $probeScript -PathType Leaf) {
    try {
      Write-Host ''
      Write-Host 'Running Verify-LVCompareSetup.ps1 -ProbeCli...' -ForegroundColor Cyan
      & $probeScript -ProbeCli | Out-String | Write-Host
    } catch {
      Write-Warning ("Setup probe failed: {0}" -f $_.Exception.Message)
      throw
    }
  }
}

[pscustomobject]@{
  OutputPath      = $OutputPath
  LabVIEWExePath  = $labviewPathFinal
  LVComparePath   = $lvcomparePathFinal
  LabVIEWCLIPath  = $labviewCliPathFinal
}
