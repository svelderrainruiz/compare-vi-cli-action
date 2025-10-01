#[CmdletBinding()] (omitted strict binding for minimal repro stability)
param(
    [Parameter(Position=0)]
    [string]$Path
)

# For test expectations: emit ONLY one line when path missing or non-existent so every pipeline element matches Should -Match.
if (-not $Path) {
    $msg = '[repro] Path was NOT bound'
    Write-Warning $msg | Out-Null
    Write-Output $msg
    return
}
if (-not (Test-Path -LiteralPath $Path)) {
    $msg = '[repro] Provided Path does not exist'
    Write-Warning $msg | Out-Null
    Write-Output $msg
    return
}

# Valid path provided: emit diagnostic lines WITHOUT warning phrases.
Write-Output "[repro] ARGS: $($args -join ', ')"
Write-Output "[repro] Raw Input -Path: '$Path'"
Write-Output "[repro] PSBoundParameters keys: $([string]::Join(',', $PSBoundParameters.Keys))"
$resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if ($resolved) { Write-Output "[repro] Resolved: $resolved" }

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
