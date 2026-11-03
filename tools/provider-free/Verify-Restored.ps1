#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Snapshot,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][string]$Out)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
[void][Reflection.Assembly]::LoadFrom((Join-Path (Split-Path (Split-Path $Snapshot)) ../OwnerIo.dll))
if((Get-ReadbackSha $Snapshot)-cne$ExpectedSha256){throw 'Snapshot identity changed'}
$doc=Get-Content -LiteralPath $Snapshot -Raw|ConvertFrom-Json -DateKind String
$result=Test-ReadbackRestored $doc;$ticks=0
foreach($r in $doc.roots){foreach($f in $r.files){$ticks++;if($null-eq$f.lastWriteUtcTicks-or[IO.File]::GetLastWriteTimeUtc($f.path).Ticks-ne[long]$f.lastWriteUtcTicks-or[IO.File]::GetCreationTimeUtc($f.path).Ticks-ne[long]$f.creationUtcTicks){$result.pass=$false;$result.errors+='numeric file ticks: '+$f.path}};foreach($d in $r.directoryMetadata){$ticks++;if([IO.Directory]::GetLastWriteTimeUtc($d.path).Ticks-ne[long]$d.lastWriteUtcTicks-or[IO.Directory]::GetCreationTimeUtc($d.path).Ticks-ne[long]$d.creationUtcTicks){$result.pass=$false;$result.errors+='numeric directory ticks: '+$d.path}}}
@{pass=$result.pass;files=$result.files;numericTickChecks=$ticks;errors=$result.errors;pid=$PID;method='fresh SHA/raw attributes/tree plus direct numeric ticks, no shared date parser'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Out
if(-not$result.pass){exit 1}
