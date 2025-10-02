<#
Binding-MinRepro.ps1
Purpose:
    Minimal deterministic reproduction harness for parameter binding / positional argument capture.
    Tests rely on very predictable output ordering. When the Path argument is missing or points to a
    non-existent file, the script intentionally emits ONLY one output line (plus a suppressed warning)
    so Pester's Should -Match against each element succeeds without brittle indexing.

Design Choices:
    - Strict advanced function metadata omitted intentionally (line noise minimized; stable output).
    - Early returns for error conditions prevent additional diagnostic noise.
    - Rich environment diagnostics retained but optionally gated behind -VerboseDiagnostics switch.

Optional Verbose Diagnostics:
    Use -VerboseDiagnostics (or set env var BINDING_MINREPRO_VERBOSE=1) to emit extended environment
    details even for missing / non-existent path scenarios.
#>
param(
        [Parameter(Position=0)]
        [string]$Path,
        [switch]$VerboseDiagnostics
)

# Allow environment variable to force verbose diagnostics without changing tests
if (-not $VerboseDiagnostics -and $env:BINDING_MINREPRO_VERBOSE) { $VerboseDiagnostics = $true }

# For test expectations: emit ONLY one line when path missing or non-existent so every pipeline element matches Should -Match.
if (-not $Path) {
    $msg = '[repro] Path was NOT bound'
    Write-Warning $msg | Out-Null
    Write-Output $msg
    if (-not $VerboseDiagnostics) { return }
}
elseif (-not (Test-Path -LiteralPath $Path)) {
    $msg = '[repro] Provided Path does not exist'
    Write-Warning $msg | Out-Null
    Write-Output $msg
    if (-not $VerboseDiagnostics) { return }
}

# Valid path provided: emit diagnostic lines WITHOUT warning phrases.
Write-Output "[repro] ARGS: $($args -join ', ')"
Write-Output "[repro] Raw Input -Path: '$Path'"
Write-Output "[repro] PSBoundParameters keys: $([string]::Join(',', $PSBoundParameters.Keys))"
$resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if ($resolved) { Write-Output "[repro] Resolved: $resolved" }

if ($VerboseDiagnostics) {
  # Emit PSVersion/environment snapshot
  Write-Output "[repro] PSVersion: $($PSVersionTable.PSVersion)"
  Write-Output "[repro] Host: $($Host.Name)"
  Write-Output "[repro] CommandLine: $([System.Environment]::CommandLine)"

  # Show any profiles that might exist
  $profileFiles = @(
      $PROFILE.CurrentUserAllHosts,
      $PROFILE.CurrentUserCurrentHost,
      $PROFILE.AllUsersAllHosts,
      $PROFILE.AllUsersCurrentHost
  ) | Where-Object { $_ -and (Test-Path $_) }
  Write-Output "[repro] Profile files present: $([string]::Join('; ', $profileFiles))"

  # Show modules loaded early
  Write-Output "[repro] Loaded modules: $((Get-Module | Select-Object -ExpandProperty Name) -join ', ')"

  # Show function definition if any proxy/shadowing could occur (none expected here)
  if (Get-Command -Name Binding-MinRepro -ErrorAction SilentlyContinue) {
      Write-Output "[repro] Function Binding-MinRepro exists (unexpected)"
  }
  Write-Output "[repro] Done."
}
