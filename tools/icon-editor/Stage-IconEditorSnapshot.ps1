param(
  [string]$SourcePath,
  [string]$ResourceOverlayRoot,
  [string]$StageName,
  [string]$WorkspaceRoot,
  [switch]$SkipValidate,
  [switch]$SkipLVCompare,
  [switch]$DryRun,
  [switch]$SkipBootstrapForValidate
)

[pscustomobject]@{
  stageRoot       = Join-Path $WorkspaceRoot $StageName
  mirrorPath      = $SourcePath
  resourceOverlay = $ResourceOverlayRoot
  skipValidate    = $SkipValidate.IsPresent
  skipLVCompare   = $SkipLVCompare.IsPresent
  dryRun          = $DryRun.IsPresent
}









