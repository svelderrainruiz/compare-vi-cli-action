[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Path
)

Write-Host "[repro] ARGS: $($args -join ', ')" -ForegroundColor Cyan
Write-Host "[repro] Raw Input -Path: '$Path'" -ForegroundColor Cyan
Write-Host "[repro] PSBoundParameters keys: $([string]::Join(',', $PSBoundParameters.Keys))" -ForegroundColor Cyan

if (-not $Path) {
    Write-Warning "[repro] Path was NOT bound (null or empty)"
} else {
    if (Test-Path -LiteralPath $Path) {
        $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        Write-Host "[repro] Resolved: $resolved" -ForegroundColor Green
    } else {
        Write-Warning "[repro] Provided Path does not exist: $Path"
    }
}

# Emit PSVersion/environment snapshot
Write-Host "[repro] PSVersion: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
Write-Host "[repro] Host: $($Host.Name)" -ForegroundColor Yellow
Write-Host "[repro] CommandLine: $([System.Environment]::CommandLine)" -ForegroundColor Yellow

# Show any profiles that might exist
$profileFiles = @(
    $PROFILE.CurrentUserAllHosts,
    $PROFILE.CurrentUserCurrentHost,
    $PROFILE.AllUsersAllHosts,
    $PROFILE.AllUsersCurrentHost
) | Where-Object { $_ -and (Test-Path $_) }

Write-Host "[repro] Profile files present: $([string]::Join('; ', $profileFiles))" -ForegroundColor Yellow

# Show modules loaded early
Write-Host "[repro] Loaded modules: $((Get-Module | Select-Object -ExpandProperty Name) -join ', ')" -ForegroundColor DarkCyan

# Show function definition if any proxy/shadowing could occur (none expected here)
if (Get-Command -Name Binding-MinRepro -ErrorAction SilentlyContinue) {
    Write-Host "[repro] Function Binding-MinRepro exists (unexpected)" -ForegroundColor Magenta
}

Write-Host "[repro] Done." -ForegroundColor Green
