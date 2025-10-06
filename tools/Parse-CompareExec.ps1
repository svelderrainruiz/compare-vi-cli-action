param(
  [string]$SearchDir = '.',
  [string]$OutJson = 'compare-outcome.json'
)
$ErrorActionPreference = 'Stop'
$paths = Get-ChildItem -Path $SearchDir -Recurse -Include compare-exec.json -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
if (-not $paths) { Write-Host 'No compare-exec.json found'; exit 0 }
$best = $paths | Select-Object -First 1
$data = Get-Content -LiteralPath $best -Raw | ConvertFrom-Json
$out = [ordered]@{
  file = $best
  diff = $data.diff
  exitCode = $data.exitCode
  durationMs = $data.durationMs
  cliPath = $data.cliPath
  command = $data.command
}
$out | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutJson -Encoding utf8
if ($env:GITHUB_STEP_SUMMARY) {
  $lines = @('### Compare Outcome','')
  $lines += ('- File: {0}' -f $best)
  $lines += ('- diff: {0}' -f $data.diff)
  $lines += ('- exitCode: {0}' -f $data.exitCode)
  $lines += ('- durationMs: {0}' -f $data.durationMs)
  $lines += ('- cliPath: {0}' -f $data.cliPath)
  $lines += ('- command: {0}' -f $data.command)
  $lines -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

