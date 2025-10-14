# ArgTokenization Module
# Provides shared constants and functions for LVCompare argument tokenization
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Canonical tokenization regex pattern
# Matches: double-quoted strings, single-quoted strings, or non-comma/non-whitespace sequences
# This pattern is intentionally simple and must not be changed without comprehensive test coverage
$script:LVCompareArgTokenPattern = '"[^\"]+"|''[^'']+''|[^,\s]+'

function Get-LVCompareArgTokenPattern {
  <#
  .SYNOPSIS
    Returns the canonical regex pattern for tokenizing LVCompare arguments.
  .DESCRIPTION
    The pattern matches:
    - Double-quoted strings (including quotes): "text"
    - Single-quoted strings (including quotes): 'text'
    - Non-comma, non-whitespace sequences: token
    
    This pattern is used consistently across CompareVI.ps1, CompareLoop.psm1, 
    Render-CompareReport.ps1, and other scripts that parse lvCompareArgs.
    
    The pattern is intentionally simple. Changes require comprehensive test coverage
    for edge cases (nested quotes, escaped quotes, etc.).
  .OUTPUTS
    String containing the regex pattern
  .EXAMPLE
    $pattern = Get-LVCompareArgTokenPattern
    $tokens = [regex]::Matches($argString, $pattern)
  #>
  return $script:LVCompareArgTokenPattern
}

function Get-LVCompareArgTokens {
  <#
  .SYNOPSIS
    Tokenize LVCompare argument specifications into a normalized list.
  .DESCRIPTION
    Accepts either a raw string (comma/whitespace delimited with optional quotes)
    or an array that may contain quoted entries. Returns tokens with outer quotes
    removed while preserving order so downstream normalization can split flag/value
    pairs consistently.
  .PARAMETER Spec
    Raw argument specification (string or array) to tokenize.
  .OUTPUTS
    String[]
  #>
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline = $true)]
    [object]$Spec
  )

  begin {
    $pattern = Get-LVCompareArgTokenPattern
    function Strip-OuterQuotes {
      param([string]$Text)
      if ($null -eq $Text) { return $Text }
      $trimmed = $Text.Trim()
      if ($trimmed.Length -eq 0) { return '' }
      if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
        if ($trimmed.Length -gt 1) { return $trimmed.Substring(1, $trimmed.Length - 2) }
        return ''
      }
      return $trimmed
    }

    function Expand-FlagToken {
      param([string]$Candidate)
      if ([string]::IsNullOrWhiteSpace($Candidate)) { return @() }
      $trimmed = $Candidate.Trim()

      if ($trimmed.StartsWith('-')) {
        $eqIdx = $trimmed.IndexOf('=')
        if ($eqIdx -gt 0) {
          $flag = $trimmed.Substring(0, $eqIdx).Trim()
          $val = $trimmed.Substring($eqIdx + 1)
          $val = Strip-OuterQuotes $val
          $pieces = @()
          if (-not [string]::IsNullOrWhiteSpace($flag)) { $pieces += $flag }
          if (-not [string]::IsNullOrWhiteSpace($val)) { $pieces += $val }
          if ($pieces.Count -gt 0) { return ,$pieces }
        }

        $spaceMatch = [regex]::Match($trimmed, '\s+')
        if ($spaceMatch.Success -and $spaceMatch.Index -gt 0) {
          $flag = $trimmed.Substring(0, $spaceMatch.Index).Trim()
          $val = $trimmed.Substring($spaceMatch.Index + $spaceMatch.Length)
          $val = Strip-OuterQuotes $val
          $parts = @()
          if (-not [string]::IsNullOrWhiteSpace($flag)) { $parts += $flag }
          if (-not [string]::IsNullOrWhiteSpace($val)) { $parts += $val }
          if ($parts.Count -gt 0) { return ,$parts }
        }
      }

      ,$trimmed
    }
  }

  process {
    if ($null -eq $Spec) { return @() }

    $rawTokens = @()
    if ($Spec -is [System.Array]) {
      foreach ($item in @($Spec)) {
        if ($null -eq $item) { continue }
        # Ignore non-string items (e.g., Pester -ForEach metadata hashtables)
        if (-not ($item -is [string])) { continue }
        $value = Strip-OuterQuotes ([string]$item)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $rawTokens += $value }
      }
    } else {
      $text = [string]$Spec
      if ([string]::IsNullOrWhiteSpace($text)) { return @() }

      $matches = [regex]::Matches($text, $pattern)
      if ($matches.Count -gt 0) {
        foreach ($match in $matches) {
          $token = Strip-OuterQuotes $match.Value
          if (-not [string]::IsNullOrWhiteSpace($token)) { $rawTokens += $token }
        }
      } else {
        $token = Strip-OuterQuotes $text
        if (-not [string]::IsNullOrWhiteSpace($token)) { $rawTokens += $token }
      }
    }

    $expanded = @()
    foreach ($token in $rawTokens) {
      $expanded += (Expand-FlagToken $token)
    }
    ,$expanded
  }
}

Export-ModuleMember -Function Get-LVCompareArgTokenPattern, Get-LVCompareArgTokens
