Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Register-PostRunRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('close-labview','close-lvcompare')][string]$Name,
    [string]$Source = 'unknown',
    [hashtable]$Metadata
  )

  $repoRoot = (Resolve-Path '.').Path
  $requestsDir = Join-Path $repoRoot 'tests/results/_agent/post/requests'
  if (-not (Test-Path -LiteralPath $requestsDir)) {
    New-Item -ItemType Directory -Force -Path $requestsDir | Out-Null
  }

  $stamp = (Get-Date).ToUniversalTime().ToString('o')
  $uid = [guid]::NewGuid().ToString('N')
  $fileName = ('{0}-{1}.json' -f $Name, $uid)
  $path = Join-Path $requestsDir $fileName

  $payload = [ordered]@{
    name   = $Name
    source = $Source
    at     = $stamp
  }
  if ($Metadata) {
    $payload.metadata = $Metadata
  }

  $payload | ConvertTo-Json -Depth 6 | Out-File -FilePath $path -Encoding utf8
  return $path
}

Export-ModuleMember -Function Register-PostRunRequest
