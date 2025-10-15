<#
Compatibility shim for Pester It -TimeoutSeconds.

Some test files use `It -TimeoutSeconds <n>`, but the installed Pester (5.7.x)
does not expose a `-TimeoutSeconds` parameter on `It`. To keep the suite
compatible without rewriting individual tests, provide a lightweight wrapper
that accepts `-TimeoutSeconds` and forwards all other parameters to
`Pester\It`, ignoring the timeout value.

This file executes during discovery and defines the wrapper only when the
current `It` does not already have a `TimeoutSeconds` parameter.
#>

try {
  $itCmd = Get-Command It -CommandType Function -ErrorAction Stop
  $hasTimeout = $itCmd.Parameters.ContainsKey('TimeoutSeconds')
} catch { $hasTimeout = $false }

if (-not $hasTimeout) {
  function It {
    [CmdletBinding(PositionalBinding = $true)]
    param(
      [Parameter(Mandatory, Position = 0)] [string] $Name,
      [Parameter(Position = 1)] [scriptblock] $Test,
      [object[]] $ForEach,
      [string[]] $Tag,
      [switch] $Skip,
      [switch] $Pending,
      [switch] $Focus,
      [int] $TimeoutSeconds
    )
    if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) { $null = $PSBoundParameters.Remove('TimeoutSeconds') }
    Pester\It @PSBoundParameters
  }
}

