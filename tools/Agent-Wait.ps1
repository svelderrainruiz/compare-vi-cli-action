param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-AgentWait {
    [CmdletBinding()] param(
        [Parameter(Position=0)][string]$Reason = 'unspecified',
        [Parameter(Position=1)][int]$ExpectedSeconds = 90,
        [Parameter()][string]$ResultsDir = 'tests/results',
        [Parameter()][int]$ToleranceSeconds = 5
    )
    $root = Resolve-Path . | Select-Object -ExpandProperty Path
    $outDir = Join-Path $ResultsDir '_agent'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $markerPath = Join-Path $outDir 'wait-marker.json'
    $now = [DateTimeOffset]::UtcNow
    $o = [ordered]@{
        schema = 'agent-wait/v1'
        reason = $Reason
        expectedSeconds = $ExpectedSeconds
        toleranceSeconds = $ToleranceSeconds
        startedUtc = $now.ToString('o')
        startedUnixSeconds = [int][Math]::Floor($now.ToUnixTimeSeconds())
        workspace = $root
    }
    $o | ConvertTo-Json -Depth 5 | Out-File -FilePath $markerPath -Encoding utf8
    $msg = "Agent wait started: reason='$Reason', expected=${ExpectedSeconds}s"
    Write-Host $msg
    if ($env:GITHUB_STEP_SUMMARY) {
        $lines = @(
            '### Agent Wait Start',
            "- Reason: $Reason",
            "- Expected: ${ExpectedSeconds}s",
            "- Marker: $markerPath"
        ) -join "`n"
        $lines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }
    return $markerPath
}

function End-AgentWait {
    [CmdletBinding()] param(
        [Parameter(Position=0)][string]$ResultsDir = 'tests/results',
        [Parameter()][int]$ToleranceSeconds = 5
    )
    $outDir = Join-Path $ResultsDir '_agent'
    $markerPath = Join-Path $outDir 'wait-marker.json'
    if (-not (Test-Path $markerPath)) {
        Write-Host '::notice::No wait marker found.'
        return $null
    }
    $start = Get-Content $markerPath -Raw | ConvertFrom-Json
    $started = [DateTimeOffset]::Parse($start.startedUtc)
    $now = [DateTimeOffset]::UtcNow
    $elapsedSec = [int][Math]::Round(($now - $started).TotalSeconds)
    # derive tolerance: prefer explicit param, fallback to marker
    $tol = if ($PSBoundParameters.ContainsKey('ToleranceSeconds')) { $ToleranceSeconds } elseif ($start.PSObject.Properties['toleranceSeconds']) { [int]$start.toleranceSeconds } else { 5 }
    $diff = [int][Math]::Abs($elapsedSec - [int]$start.expectedSeconds)
    $withinMargin = ($diff -le $tol)

    $result = [ordered]@{
        schema = 'agent-wait-result/v1'
        reason = $start.reason
        expectedSeconds = $start.expectedSeconds
        startedUtc = $start.startedUtc
        endedUtc = $now.ToString('o')
        elapsedSeconds = $elapsedSec
        toleranceSeconds = $tol
        differenceSeconds = $diff
        withinMargin = $withinMargin
        markerPath = $markerPath
    }
    $lastPath = Join-Path $outDir 'wait-last.json'
    $logPath = Join-Path $outDir 'wait-log.ndjson'
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $lastPath -Encoding utf8
    ($result | ConvertTo-Json -Depth 5) | Out-File -FilePath $logPath -Append -Encoding utf8
    # Keep marker for chainable waits; caller may remove if desired
    $summary = @(
        '### Agent Wait Result',
        "- Reason: $($result.reason)",
        "- Elapsed: ${elapsedSec}s",
        "- Expected: $($result.expectedSeconds)s",
        "- Tolerance: ${tol}s",
        "- Difference: ${diff}s",
        "- Within Margin: $withinMargin"
    ) -join "`n"
    Write-Host $summary
    if ($env:GITHUB_STEP_SUMMARY) {
        $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
    }
    return $result
}

# Export only when running inside a module context
try {
    if ($PSVersionTable -and $ExecutionContext -and $ExecutionContext.SessionState.Module) {
        Export-ModuleMember -Function Start-AgentWait, End-AgentWait
    }
} catch {
    # Ignore when not in a module context
}
