#Requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$BaseVi,
  [Parameter(Mandatory = $true)][string]$HeadVi,
  [ValidateSet('normal','cli-suppressed','git-context','duplicate-window')]
  [string]$Mode = 'normal',
  [string]$ResultsRoot,
  [switch]$ProbeSetup,
[switch]$AutoConfig,
[switch]$Stateless,
[switch]$RenderReport,
[switch]$UseStub,
[string]$LabVIEWVersion,
[ValidateSet('32','64')]
[string]$LabVIEWBitness,
[ValidateSet('full','legacy')]
[string]$NoiseProfile = 'full',
[switch]$CheckViServer = $true,
[string]$ArchiveDir = 'tests/results/_agent/local-diff/latest',
[string]$ArchiveZip = 'tests/results/_agent/local-diff/latest.zip'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  try { return (git -C (Get-Location).Path rev-parse --show-toplevel 2>$null).Trim() } catch { return (Get-Location).Path }
}

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

$repoRoot = Resolve-RepoRoot
$vendorModule = Join-Path $repoRoot 'tools' 'VendorTools.psm1'
if (Test-Path -LiteralPath $vendorModule -PathType Leaf) {
  Import-Module $vendorModule -Force | Out-Null
}

$verifyScript = Join-Path $repoRoot 'tools' 'Verify-LocalDiffSession.ps1'
if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
  throw "Verify-LVCompare script not found at $verifyScript"
}

function Resolve-LabVIEWCandidateForSession {
  param(
    [string]$Version,
    [string]$Bitness
  )

  if (-not (Get-Command Get-LabVIEWCandidateExePaths -ErrorAction SilentlyContinue)) {
    return $null
  }

  $candidates = @(Get-LabVIEWCandidateExePaths)
  if ($Version) {
    $preferred = @($candidates | Where-Object { $_ -match ("LabVIEW\s+$([regex]::Escape($Version))") })
    if ($preferred.Count -eq 0) {
      $preferred = @($candidates | Where-Object { $_ -match $Version })
    }
    if ($preferred.Count -gt 0) { $candidates = $preferred }
  }

  if ($Bitness -eq '32') {
    $preferred32 = @($candidates | Where-Object { $_ -match '(?i)(\(32-bit\)|Program Files \(x86\))' })
    if ($preferred32.Count -gt 0) { $candidates = $preferred32 }
  } elseif ($Bitness -eq '64') {
    $preferred64 = @($candidates | Where-Object { $_ -notmatch '(?i)(\(32-bit\)|Program Files \(x86\))' })
    if ($preferred64.Count -gt 0) { $candidates = $preferred64 }
  }

  if ($candidates.Count -gt 0) { return $candidates[0] }
  return $null
}

$invokeParams = @{
  BaseVi = $BaseVi
  HeadVi = $HeadVi
  Mode   = $Mode
  NoiseProfile = $NoiseProfile
}
if ($ResultsRoot) { $invokeParams['ResultsRoot'] = $ResultsRoot }
if ($ProbeSetup.IsPresent)  { $invokeParams['ProbeSetup']  = $true }
if ($AutoConfig.IsPresent)  { $invokeParams['AutoConfig']  = $true }
if ($Stateless.IsPresent)   { $invokeParams['Stateless']   = $true }
if ($RenderReport.IsPresent){ $invokeParams['RenderReport']= $true }
if ($UseStub.IsPresent)     { $invokeParams['UseStub']     = $true }
if ($LabVIEWVersion)        { $invokeParams['LabVIEWVersion'] = $LabVIEWVersion }
if ($LabVIEWBitness)        { $invokeParams['LabVIEWBitness'] = $LabVIEWBitness }

if ($CheckViServer.IsPresent -and -not $UseStub.IsPresent -and (Get-Command Get-LabVIEWIniValue -ErrorAction SilentlyContinue)) {
  $candidateExe = Resolve-LabVIEWCandidateForSession -Version $LabVIEWVersion -Bitness $LabVIEWBitness
  if ($candidateExe) {
    Write-Verbose ("Checking VI Server settings for {0}" -f $candidateExe)
    $iniPath = $null
    try { $iniPath = Get-LabVIEWIniPath -LabVIEWExePath $candidateExe } catch {}
    if ($iniPath -and (Test-Path -LiteralPath $iniPath -PathType Leaf)) {
      $tcpEnabled = $null
      try { $tcpEnabled = Get-LabVIEWIniValue -LabVIEWIniPath $iniPath -Key 'server.tcp.enabled' } catch {}
      if ($tcpEnabled -and $tcpEnabled.Trim().ToUpperInvariant() -eq 'TRUE') {
        $tcpPort = $null
        try { $tcpPort = Get-LabVIEWIniValue -LabVIEWIniPath $iniPath -Key 'server.tcp.port' } catch {}
        if ($tcpPort) {
          Write-Verbose ("VI Server TCP port: {0}" -f $tcpPort)
        } else {
          Write-Verbose 'VI Server enabled but port not found in ini.'
        }
      } else {
        Write-Warning ("LabVIEW VI Server appears disabled for {0} (server.tcp.enabled={1}). Enable it via Tools -> Options -> VI Server." -f $candidateExe, ($tcpEnabled ?? 'null'))
      }
    } else {
      Write-Warning ("Unable to locate LabVIEW.ini for {0} to verify VI Server settings." -f $candidateExe)
    }
  } else {
    Write-Warning 'Unable to resolve a LabVIEW.exe candidate for VI Server checks.'
  }
}

$sessionResult = & $verifyScript @invokeParams
if ($LASTEXITCODE -ne 0 -and $sessionResult -isnot [System.Management.Automation.Language.NullString]) {
  Write-Warning ("Verify-LocalDiffSession exited with code {0}" -f $LASTEXITCODE)
}
if (-not $sessionResult) {
  throw 'Verify-LocalDiffSession returned no session information.'
}

$resultsDir = if ($sessionResult.PSObject.Properties['resultsDir'] -and $sessionResult.resultsDir) {
  $sessionResult.resultsDir
} elseif ($ResultsRoot) {
  if ([System.IO.Path]::IsPathRooted($ResultsRoot)) { $ResultsRoot } else { Join-Path $repoRoot $ResultsRoot }
} else {
  throw 'Unable to determine results directory from session output.'
}

if (-not (Test-Path -LiteralPath $resultsDir -PathType Container)) {
  Write-Warning ("Results directory '{0}' was not found." -f $resultsDir)
} else {
  if ($ArchiveDir) {
    $archiveDirResolved = if ([System.IO.Path]::IsPathRooted($ArchiveDir)) { $ArchiveDir } else { Join-Path $repoRoot $ArchiveDir }
    if (Test-Path -LiteralPath $archiveDirResolved -PathType Container) {
      Remove-Item -LiteralPath $archiveDirResolved -Recurse -Force
    }
    Ensure-Directory -Path $archiveDirResolved
    Copy-Item -Path (Join-Path $resultsDir '*') -Destination $archiveDirResolved -Recurse -Force
    Write-Host ("Local diff artifacts copied to {0}" -f $archiveDirResolved)
  }

  if ($ArchiveZip) {
    $archiveZipResolved = if ([System.IO.Path]::IsPathRooted($ArchiveZip)) { $ArchiveZip } else { Join-Path $repoRoot $ArchiveZip }
    $zipParent = Split-Path -Parent $archiveZipResolved
    if ($zipParent) { Ensure-Directory -Path $zipParent }
    if (Test-Path -LiteralPath $archiveZipResolved -PathType Leaf) {
      Remove-Item -LiteralPath $archiveZipResolved -Force
    }
    Compress-Archive -Path (Join-Path $resultsDir '*') -DestinationPath $archiveZipResolved -Force
    Write-Host ("Local diff artifacts zipped to {0}" -f $archiveZipResolved)
  }
}

return $sessionResult
