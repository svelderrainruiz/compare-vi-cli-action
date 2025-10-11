Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-TickCounter {
  param([int]$TickMilliseconds = 1)
  if ($TickMilliseconds -lt 1) { $TickMilliseconds = 1 }
  $counter = [pscustomobject]@{
    stopwatch       = [System.Diagnostics.Stopwatch]::StartNew()
    ticks           = 0
    tickMilliseconds= $TickMilliseconds
  }
  return $counter
}

function Wait-Tick {
  param(
    [pscustomobject]$Counter,
    [int]$Milliseconds = 1
  )
  if ($Milliseconds -lt 1) { $Milliseconds = 1 }
  [System.Threading.Thread]::Sleep($Milliseconds)
  if ($Counter) { $Counter.ticks += 1 }
  return $Counter
}

function Read-TickCounter {
  param([pscustomobject]$Counter)
  if (-not $Counter) { return $null }
  $elapsedMs = 0.0
  if ($Counter.stopwatch) { $elapsedMs = $Counter.stopwatch.Elapsed.TotalMilliseconds }
  return [pscustomobject]@{
    ticks     = $Counter.ticks
    elapsedMs = [double]::Round($elapsedMs,3)
    intervalMs= $Counter.tickMilliseconds
  }
}

function Stop-TickCounter {
  param([pscustomobject]$Counter)
  if ($Counter -and $Counter.stopwatch -and $Counter.stopwatch.IsRunning) {
    $Counter.stopwatch.Stop()
  }
}

Export-ModuleMember -Function Start-TickCounter,Wait-Tick,Read-TickCounter,Stop-TickCounter
