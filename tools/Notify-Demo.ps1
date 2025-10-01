param(
  [string]$Status,
  [int]$Failed,
  [int]$Tests,
  [int]$Skipped,
  [int]$RunSequence,
  [string]$Classification
)
# Simple demo notify script. Writes a concise line plus environment reflection.
$line = "Notify: Run#$RunSequence Status=$Status Failed=$Failed Tests=$Tests Skipped=$Skipped Class=$Classification"
Write-Output $line
if ($env:WATCH_STATUS) {
  Write-Output "Env WATCH_STATUS=$($env:WATCH_STATUS)"
}
