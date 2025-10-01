# CompareLoop.TestHelpers - internal test helper module
# Provides closure-based executor factory for Invoke-IntegrationCompareLoop tests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-LoopExecutor {
  <#
  .SYNOPSIS
    Creates a closure-based executor scriptblock with optional artificial delay.
  .PARAMETER DelayMilliseconds
    Milliseconds to sleep before returning 0. Default 0.
  .OUTPUTS
    ScriptBlock (param($cli,$base,$head,$argList)) returning exit code 0.
  #>
  [CmdletBinding()] param([int]$DelayMilliseconds = 0)
  $captured = [int]$DelayMilliseconds
  return {
    param($cli,$b,$h,$argList)
    if ($captured -gt 0) { Start-Sleep -Milliseconds $captured }
    0
  }.GetNewClosure()
}

Export-ModuleMember -Function New-LoopExecutor
