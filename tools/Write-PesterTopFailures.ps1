<#
.SYNOPSIS
  Append a concise “Top Failures” section to the job summary from Pester outputs.
#>
[CmdletBinding()]
param(
  [string]$ResultsDir = 'tests/results',
  [int]$Top = 5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_STEP_SUMMARY) { return }

function Add-Lines([string[]]$lines) { $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8 }

$failJson = Join-Path $ResultsDir 'pester-failures.json'
$nunitXml  = Join-Path $ResultsDir 'pester-results.xml'

$items = @()
if (Test-Path -LiteralPath $failJson) {
  try {
    $arr = Get-Content -LiteralPath $failJson -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($f in $arr) {
      $file = ''
      $line = ''
      if ($f.PSObject.Properties.Name -contains 'file') { $file = [string]$f.file }
      if ($f.PSObject.Properties.Name -contains 'line') { $line = [string]$f.line }
      $msg  = ''
      if ($f.PSObject.Properties.Name -contains 'message') { $msg = [string]$f.message }
      $name = ''
      if ($f.PSObject.Properties.Name -contains 'name') { $name = [string]$f.name }
      $items += [pscustomobject]@{ name=$name; file=$file; line=$line; message=$msg }
    }
  } catch {}
}
elseif (Test-Path -LiteralPath $nunitXml) {
  try {
    [xml]$xml = Get-Content -LiteralPath $nunitXml -Raw
    $nodes = $xml.SelectNodes('//test-case[failure]')
    foreach ($n in $nodes) {
      $name = $n.name
      $msg  = $n.failure.message
      $stack = $n.failure.'stack-trace'
      $file = ''
      $line = ''
      if ($stack) {
        $m = [regex]::Match($stack,'(?m)([A-Z]:\\[^\r\n]+?):line\s+(\d+)')
        if ($m.Success) { $file = $m.Groups[1].Value; $line = $m.Groups[2].Value }
      }
      $items += [pscustomobject]@{ name=$name; file=$file; line=$line; message=$msg }
    }
  } catch {}
}

if (-not $items -or $items.Count -eq 0) {
  Add-Lines @('### Top Failures','- (none)')
  return
}

$take = [Math]::Min($Top, $items.Count)
$lines = @('### Top Failures','')
for ($i=0; $i -lt $take; $i++) {
  $it = $items[$i]
  $loc = if ($it.file) { if ($it.line) { " ($($it.file):$($it.line))" } else { " ($($it.file))" } } else { '' }
  $msg = if ($it.message) { ($it.message -split "`n")[0] } else { '' }
  $title = if ($it.name) { $it.name } else { if ($msg) { $msg } else { 'Failure' } }
  $lines += ("- {0}{1}" -f $title,$loc)
  if ($msg) { $lines += ("  - {0}" -f $msg) }
}
Add-Lines $lines

