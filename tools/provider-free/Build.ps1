#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Plan,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][int]$Go,[switch]$CheckPlanOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
. (Join-Path $PSScriptRoot Environment.ps1)
. (Join-Path $PSScriptRoot Data.ps1)
$fm2CpuPlan=Read-Fm2Plan $Plan $ExpectedSha256 'fm2.cpu-plan@1'
if($CheckPlanOnly){@{scopePass=$true;planType=$fm2CpuPlan.GetType().FullName;game=$false;hooks=$false;owner=$false;lease=$false}|ConvertTo-Json;return}
Assert-Bo3Source $fm2CpuPlan.source;Assert-Bo3Rows $fm2CpuPlan.sourcePins;Assert-Bo3Rows $fm2CpuPlan.toolPins;Assert-Bo3Rows $fm2CpuPlan.sdkPins
Assert-Bo3Rows $fm2CpuPlan.hostAudit.pins
$e=$fm2CpuPlan.evidence;$out=Join-Path $e cpu-result.json
if(Test-Path -LiteralPath $out){throw 'One CPU invocation per frozen plan'}
foreach($name in @('Guard.dll','Snapshot.dll','OwnerIo.dll')){$origin=Join-Path ([IO.Path]::GetDirectoryName($fm2CpuPlan.cheap[1].path)) $name;Copy-Item -LiteralPath $origin -Destination $e;[void][Reflection.Assembly]::LoadFrom((Join-Path $e $name))}
$leaseName='napo-forza2-cpu-'+$Go;$leaseTool='E:\Source\dbce-project-mgmt\tools\Rig-Lease.ps1';$receipt=Join-Path $env:LOCALAPPDATA ('dbce/claude-lease-'+$leaseName+'.json')
$cpuContext=@{lease=$null;clock=[Diagnostics.Stopwatch]::StartNew();workSeconds=1710;epoch=[DateTime]::UtcNow.Ticks;seen=@{}}
$result=[ordered]@{status='INCOMPLETE';go=$Go;planSha256=$ExpectedSha256;source=$fm2CpuPlan.source.commit;game=$false;hooks=$false;ownerWrite=$false;install=$false;publicPush=$false;released=$false;jobEmpty=$false;failure=$null}
$allowed=@($fm2CpuPlan.tools.Values)+@($fm2CpuPlan.tools.PSObject.Properties.Value)+@($env:ComSpec,(Join-Path ([Environment]::GetFolderPath('System')) conhost.exe),'C:\Program Files\LLVM\bin\lld-link.exe')
function CpuGuard {
 Assert-Bo3Budget $cpuContext
 if(-not$cpuContext.lease-or-not(Test-Path -LiteralPath $cpuContext.lease.path)-or(Get-Content -LiteralPath $cpuContext.lease.path -Raw).Trim()-cne$cpuContext.lease.token){throw 'Exact CPU lease lost'}
 $bad=@()
 foreach($childPid in @([CannonballLive]::JobPids())){
  try{$id=[CannonballLive]::ProcessIdentity($childPid)}catch{if(Get-Process -Id $childPid -ErrorAction SilentlyContinue){throw};continue}
  $key=[string]$id.pid+':'+[string]$id.birth
  if(-not$cpuContext.seen.ContainsKey($key)){$cpuContext.seen[$key]=$id;Write-Bo3Json (Join-Path $e cpu-identities.json) @($cpuContext.seen.Values)}
  if($id.birth-lt$cpuContext.epoch-or$id.image-notin$allowed){$bad+=$id}
 }
 if($bad.Count){throw ('Unadmitted CPU child: '+($bad.image-join','))}
}
try{
 if(Test-Path -LiteralPath $receipt){throw 'CPU named receipt already exists'}
 &$leaseTool -Enter -Name $leaseName -IdleMinutes 0 -Purpose "FM2 native CPU only GO$Go, jobs2, no launch" | Out-File (Join-Path $e lease-enter.txt)
 $cpuContext.lease=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;CpuGuard
 Set-Fm2BuildEnvironment $e {CpuGuard};CpuGuard
 if(Test-Path -LiteralPath $fm2CpuPlan.build){throw 'Fresh isolated build output required'}
 $result.sdkRows=Get-Bo3Rows $fm2CpuPlan.sdk
 Assert-Bo3Rows $fm2CpuPlan.sdkPins
 $result.dataRows=@(Copy-Fm2Tree (Join-Path $fm2CpuPlan.owner game) (Join-Path $e data) {CpuGuard})
 $result.dataContract=Test-Fm2Disc $result.dataRows (Join-Path $fm2CpuPlan.source.root launcher/data/game_files.sha256)
 $result.userRows=@(Copy-Fm2Tree $fm2CpuPlan.ownerProfile (Join-Path $e user) {CpuGuard})
 $result.cacheRows=@(Copy-Fm2Tree $fm2CpuPlan.ownerCache (Join-Path $e cache) {CpuGuard})
 $cmakeArgs=@('-S',$fm2CpuPlan.source.root,'-B',$fm2CpuPlan.build,'-G','Ninja',('-DCMAKE_MAKE_PROGRAM='+$fm2CpuPlan.tools.ninja),('-DCMAKE_C_COMPILER='+$fm2CpuPlan.tools.clang),('-DCMAKE_CXX_COMPILER='+$fm2CpuPlan.tools.clangxx),('-DCMAKE_PREFIX_PATH='+$fm2CpuPlan.sdk),'-DCMAKE_BUILD_TYPE=Release','-DFORZA2_BUILD_LAUNCHER=OFF','-DCMAKE_EXPORT_COMPILE_COMMANDS=ON')
 Invoke-Bo3Owned $fm2CpuPlan.tools.cmake $cmakeArgs $fm2CpuPlan.source.root configure $e 120 {CpuGuard}|Out-Null;CpuGuard
 Invoke-Bo3Owned $fm2CpuPlan.tools.cmake @('--build',$fm2CpuPlan.build,'--target','forza2','--parallel','2') $fm2CpuPlan.source.root build $e 1560 {CpuGuard}|Out-Null;CpuGuard
 $exe=Join-Path $fm2CpuPlan.build forza2.exe
 if(-not(Test-Path -LiteralPath $exe)){throw 'Native candidate absent'}
 Invoke-Bo3Owned $fm2CpuPlan.tools.readobj @('--coff-imports',$exe) $fm2CpuPlan.source.root pe-imports $e 20 {CpuGuard}|Out-Null;CpuGuard
 $result.products=@(Get-ChildItem -LiteralPath $fm2CpuPlan.build -File|Where-Object Extension -in '.exe','.dll','.toml'|ForEach-Object{@{path=$_.FullName;bytes=$_.Length;sha256=(Get-ReadbackSha $_.FullName)}})
 $importFiles=@((Join-Path $e pe-imports.stdout.txt))
 foreach($dll in @($result.products|Where-Object path -like '*.dll')){$label='pe-'+[IO.Path]::GetFileNameWithoutExtension($dll.path);Invoke-Bo3Owned $fm2CpuPlan.tools.readobj @('--coff-imports',$dll.path) $fm2CpuPlan.source.root $label $e 20 {CpuGuard}|Out-Null;CpuGuard;$importFiles+=(Join-Path $e ($label+'.stdout.txt'))}
 & $fm2CpuPlan.hostAudit.reader -ImportsPath $importFiles -CatalogPath $fm2CpuPlan.hostAudit.catalog -Out (Join-Path $e host-surface-inventory.json) | Out-Null
 $result.hostSurfaceInventory=@{path=(Join-Path $e host-surface-inventory.json);sha256=(Get-ReadbackSha (Join-Path $e host-surface-inventory.json));note='Import signals only; explicit resolution required before any isolation claim'}
 $result.generated=@(Get-Bo3Rows (Join-Path $fm2CpuPlan.source.root generated))
 $result.guardSha256=Get-ReadbackSha (Join-Path $e Guard.dll);$result.snapshotSha256=Get-ReadbackSha (Join-Path $e Snapshot.dll);$result.ownerIoSha256=Get-ReadbackSha (Join-Path $e OwnerIo.dll)
 $result.status='PASS'
}catch{$result.status='BLOCKED';$result.failure=$_.Exception.ToString()}
finally{
 if(-not$cpuContext.lease-and(Test-Path -LiteralPath $receipt)){$maybe=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json;if((Test-Path -LiteralPath $maybe.path)-and(Get-Content -LiteralPath $maybe.path -Raw).Trim()-ceq$maybe.token){$cpuContext.lease=$maybe}}
 if([CannonballLive]::JobPids().Length){Write-Bo3Json (Join-Path $e cpu-before-owned-termination.json) @([CannonballLive]::JobPids()|ForEach-Object{[CannonballLive]::ProcessIdentity($_)});[CannonballLive]::KillOwned();$result.ownedStop=$true}
 $until=[DateTime]::UtcNow.AddSeconds(30);while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){[Threading.Thread]::Sleep(25)}
 $result.jobEmpty=[CannonballLive]::JobPids().Length-eq0
 if($result.jobEmpty){[CannonballLive]::ReleaseJob();if($cpuContext.lease){&$leaseTool -Exit -Name $leaseName|Out-File (Join-Path $e lease-exit.txt);$result.released=-not(Test-Path -LiteralPath $receipt)}}
 $result.seconds=$cpuContext.clock.Elapsed.TotalSeconds;$result.identities=@($cpuContext.seen.Values);Write-Bo3Json $out $result
}
@{status=$result.status;go=$Go;released=$result.released;jobEmpty=$result.jobEmpty;failure=$result.failure;seconds=$result.seconds;path=$out}|ConvertTo-Json
if($result.status-cne'PASS'-or-not$result.released-or-not$result.jobEmpty){throw 'CPU qualification incomplete; exact state retained'}
