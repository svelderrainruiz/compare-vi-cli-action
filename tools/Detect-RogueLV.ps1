param(
  [string]$ResultsDir = 'tests/results',
  [int]$LookBackSeconds = 900,
  [switch]$FailOnRogue,
  [switch]$AppendToStepSummary,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$noticeDir = if ($env:LV_NOTICE_DIR) { $env:LV_NOTICE_DIR } else { Join-Path $ResultsDir '_lvcompare_notice' }
$now = Get-Date
$cutoff = $now.AddSeconds(-[math]::Abs($LookBackSeconds))

$noticedLC = New-Object System.Collections.Generic.HashSet[int]
$noticedLV = New-Object System.Collections.Generic.HashSet[int]

if (Test-Path -LiteralPath $noticeDir) {
  $files = Get-ChildItem -Path $noticeDir -Filter 'notice-*.json' | Where-Object { $_.LastWriteTime -ge $cutoff } | Sort-Object LastWriteTime
  foreach($f in $files){
    try {
      $j = Get-Content $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
      if ($j.phase -eq 'post-start' -and $j.PSObject.Properties['pid']) {
        [void]$noticedLC.Add([int]$j.pid)
      }
      if ($j.phase -eq 'post-complete' -and $j.PSObject.Properties['labviewPids']){
        foreach($procId in $j.labviewPids){ try { [void]$noticedLV.Add([int]$procId) } catch {} }
      }
    } catch {}
  }
}

$liveLC = @(); $liveLV = @()
try { $liveLC = @(Get-Process -Name 'LVCompare' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) } catch {}
try { $liveLV = @(Get-Process -Name 'LabVIEW'   -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) } catch {}

function Diff-Rogue([int[]]$live, $noticedSet){
  $rogue = @()
  foreach($procId in $live){ if (-not $noticedSet.Contains([int]$procId)) { $rogue += [int]$procId } }
  return ,$rogue
}

$rogueLC = Diff-Rogue $liveLC $noticedLC
$rogueLV = Diff-Rogue $liveLV $noticedLV

$out = [ordered]@{
  schema = 'rogue-lv-detection/v1'
  generatedAt = $now.ToString('o')
  lookbackSeconds = $LookBackSeconds
  noticeDir = $noticeDir
  live = [ordered]@{ lvcompare = $liveLC; labview = $liveLV }
  noticed = [ordered]@{ lvcompare = @($noticedLC); labview = @($noticedLV) }
  rogue = [ordered]@{ lvcompare = $rogueLC; labview = $rogueLV }
}

if (-not $Quiet) {
  $lines = @('### Rogue LV Detection','')
  $lines += ('- Lookback: {0}s' -f $LookBackSeconds)
  $lines += ('- Live: LVCompare={0} LabVIEW={1}' -f ($liveLC -join ','), ($liveLV -join ','))
  $lines += ('- Noticed: LVCompare={0} LabVIEW={1}' -f ((@($noticedLC)) -join ','), ((@($noticedLV)) -join ','))
  $lines += ('- Rogue: LVCompare={0} LabVIEW={1}' -f ($rogueLC -join ','), ($rogueLV -join ','))
  $txt = $lines -join [Environment]::NewLine
  Write-Host $txt
  if ($AppendToStepSummary -and $env:GITHUB_STEP_SUMMARY) { $txt | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8 }
}

$json = $out | ConvertTo-Json -Depth 6
Write-Output $json

if ($FailOnRogue -and ($rogueLC.Count -gt 0 -or $rogueLV.Count -gt 0)) { exit 3 } else { exit 0 }


