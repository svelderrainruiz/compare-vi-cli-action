param(
  [string]$ExtensionDir = "vscode/comparevi-helper",
  [string]$OutDir = "artifacts/vsix",
  [switch]$Install,
  [switch]$BumpPatch,
  [string]$VsceVersion = "latest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[ext-build] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "[ext-build] $msg" -ForegroundColor Yellow }
function Write-Err ([string]$msg) { Write-Host "[ext-build] $msg" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $ExtensionDir)) {
  Write-Err "Extension directory not found: $ExtensionDir"
  exit 1
}

$pkgPath = Join-Path $ExtensionDir 'package.json'
if (-not (Test-Path -LiteralPath $pkgPath)) {
  Write-Err "Missing package.json at $pkgPath"
  exit 1
}

Write-Info "Loading manifest: $pkgPath"
$pkgRaw = Get-Content -LiteralPath $pkgPath -Raw -ErrorAction Stop
$pkg = $pkgRaw | ConvertFrom-Json -ErrorAction Stop

if ($BumpPatch) {
  $ver = [string]$pkg.version
  if ([string]::IsNullOrWhiteSpace($ver)) {
    Write-Err "Cannot bump version: missing 'version' in package.json"
    exit 1
  }
  $parts = $ver.Split('.')
  if ($parts.Count -lt 3) { $parts = @($parts + (0..(2 - ($parts.Count))).ForEach({ '0' })) }
  $patch = 0
  if (-not [int]::TryParse($parts[-1], [ref]$patch)) { $patch = 0 }
  $patch++
  $newVer = "{0}.{1}.{2}" -f $parts[0], $parts[1], $patch
  Write-Info "Bumping version: $ver -> $newVer"
  $pkg.version = $newVer
  # Preserve formatting by re-serializing; keep stable indentation
  $pkg | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $pkgPath -Encoding UTF8
}

$publisher = [string]$pkg.publisher
$name = [string]$pkg.name
$version = [string]$pkg.version
if ([string]::IsNullOrWhiteSpace($publisher) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) {
  Write-Err "package.json must include 'publisher', 'name', and 'version'"
  exit 1
}

$vsixName = "$publisher.$name-$version.vsix"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$resolvedOutDir = (Resolve-Path -LiteralPath $OutDir -ErrorAction Stop).Path
$outPath = Join-Path $resolvedOutDir $vsixName

# Detect Node/npm/npx
function Test-Cmd([string]$cmd) {
  $oldEA = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
  try { & $cmd --version | Out-Null; return $true } catch { return $false } finally { $ErrorActionPreference = $oldEA }
}

if (-not (Test-Cmd 'node')) { Write-Warn 'Node.js not found on PATH. Packaging requires Node/npm.' }
if (-not (Test-Cmd 'npm')) { Write-Warn 'npm not found on PATH. npx may also be missing.' }
if (-not (Test-Cmd 'npx')) { Write-Warn 'npx not found on PATH. Will attempt npm exec fallback.' }

Write-Info "Packaging with vsce ($VsceVersion) -> $outPath"

function Resolve-CmdPath([string]$cmd) {
  if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
  $candidates = @()
  try {
    $candidates += Get-Command $cmd -CommandType Application -ErrorAction Stop
  } catch {}
  try {
    $candidates += Get-Command $cmd -ErrorAction Stop
  } catch {}
  foreach ($candidate in $candidates) {
    $source = $candidate.Source
    if (-not $source) { continue }
    if ($source.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
      $base = [System.IO.Path]::ChangeExtension($source, '.cmd')
      if ($base -and (Test-Path -LiteralPath $base)) { return $base }
      $base = [System.IO.Path]::ChangeExtension($source, '.bat')
      if ($base -and (Test-Path -LiteralPath $base)) { return $base }
    }
    return $source
  }
  return $null
}

$packageCmd = $null
$packageArgs = $null
if (Test-Cmd 'npx') {
  $packageCmd = 'npx'
  $packageArgs = @('--yes', "@vscode/vsce@$VsceVersion", 'package', '--no-dependencies', '--out', $outPath)
} elseif (Test-Cmd 'npm') {
  # npm exec fallback
  $packageCmd = 'npm'
  $packageArgs = @('exec', "@vscode/vsce@$VsceVersion", '--', 'package', '--no-dependencies', '--out', $outPath)
} else {
  Write-Err 'Neither npx nor npm available. Please install Node.js (https://nodejs.org) and ensure npx is on PATH.'
  exit 1
}

$packageExe = Resolve-CmdPath($packageCmd)
if (-not $packageExe) { $packageExe = $packageCmd }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $packageExe
foreach ($arg in $packageArgs) {
  [void]$psi.ArgumentList.Add($arg)
}
$psi.WorkingDirectory = (Resolve-Path $ExtensionDir)
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()
Write-Host $stdout
if ($proc.ExitCode -ne 0) {
  Write-Host $stderr
  Write-Err "vsce packaging failed with exit code $($proc.ExitCode)"
  exit $proc.ExitCode
}

if (-not (Test-Path -LiteralPath $outPath)) {
  Write-Err "Packaging succeeded but VSIX not found: $outPath"
  exit 1
}

Write-Info "Created: $outPath"

if ($Install) {
  Write-Info 'Attempting to install into VS Code...'
  $candidates = @('code', 'code-insiders', 'codium')
  $codeExe = $null
  foreach ($c in $candidates) {
    if (Test-Cmd $c) { $codeExe = $c; break }
  }
  if (-not $codeExe) {
    Write-Warn 'VS Code CLI not found on PATH (code/code-insiders). Skipping install.'
  } else {
    $installArgs = @('--install-extension', $outPath, '--force')
    $psi2 = New-Object System.Diagnostics.ProcessStartInfo
    $psi2.FileName = Resolve-CmdPath($codeExe) ?? $codeExe
    foreach ($arg in $installArgs) {
      [void]$psi2.ArgumentList.Add($arg)
    }
    $psi2.RedirectStandardOutput = $true
    $psi2.RedirectStandardError = $true
    $psi2.UseShellExecute = $false
    $p2 = [System.Diagnostics.Process]::Start($psi2)
    $o2 = $p2.StandardOutput.ReadToEnd()
    $e2 = $p2.StandardError.ReadToEnd()
    $p2.WaitForExit()
    Write-Host $o2
    if ($p2.ExitCode -ne 0) {
      Write-Host $e2
      Write-Err "VS Code install failed with exit code $($p2.ExitCode)"
      exit $p2.ExitCode
    }
    Write-Info 'Extension installed successfully.'
  }
}

exit 0
