Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Dot-sourcing policy' -Tag 'Policy' {
  It 'rejects dot-sourcing in test files (use modules/shims instead)' -Skip:($env:ENFORCE_NO_DOT_SOURCING -ne '1') {
    $testRoot = Split-Path -Parent $PSCommandPath
    $supportRoot = (Resolve-Path -LiteralPath (Join-Path $testRoot 'support')).Path
    $testFiles = Get-ChildItem -Path $testRoot -Filter '*.Tests.ps1' -Recurse | Where-Object {
      -not $_.FullName.StartsWith($supportRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $violations = New-Object System.Collections.Generic.List[object]

    foreach ($file in $testFiles) {
      $lines = Get-Content -LiteralPath $file.FullName
      for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $lineText = $lines[$idx]
        if ($lineText -match '^\s*\.\s+') {
          $violations.Add([pscustomobject]@{
            File = $file.FullName
            Line = $idx + 1
            Text = $lineText.Trim()
          })
        }
      }
    }

    if ($violations.Count -gt 0) {
      $details = $violations | ForEach-Object { "{0}:{1} => {2}" -f $_.File,$_.Line,$_.Text }
      $joined = ($details -join "`n - ")
      throw "Dot-sourcing detected in test files:`n - $joined"
    }
  }
}
