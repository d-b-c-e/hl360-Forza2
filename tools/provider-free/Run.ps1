#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Plan,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][int]$Go,[switch]$CheckPlanOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
. (Join-Path $PSScriptRoot JobPolicy.ps1)
. (Join-Path $PSScriptRoot Lifecycle.ps1)
$fm2LivePlan=Read-Fm2Plan $Plan $ExpectedSha256 'fm2.live-plan@1'
if($CheckPlanOnly){@{scopePass=$true;planType=$fm2LivePlan.GetType().FullName;game=$false;lease=$false;hooks=$false;owner=$false}|ConvertTo-Json;return}
if(-not$fm2LivePlan.normalCloseOnly-or$fm2LivePlan.ownerWrite){throw 'Normal close/private state scope required'}
Assert-Bo3Source $fm2LivePlan.source;Assert-Bo3Rows $fm2LivePlan.sourcePins;Assert-Bo3Rows $fm2LivePlan.products;Assert-Bo3Rows $fm2LivePlan.captureRows
if(-not$fm2LivePlan.hostSurfacePins.Count){throw 'Frozen host-surface evidence required'};Assert-Bo3Rows $fm2LivePlan.hostSurfacePins
foreach($rows in @($fm2LivePlan.dataRows,$fm2LivePlan.userRows,$fm2LivePlan.cacheRows)){Assert-Bo3Rows $rows}
$e=$fm2LivePlan.evidence
if(-not$fm2LivePlan.cpuReceiptPath-or(Get-ReadbackSha $fm2LivePlan.cpuReceiptPath)-cne$fm2LivePlan.cpuSha256){throw 'CPU receipt changed'}
if($fm2LivePlan.privateInputReceipt){Assert-Bo3Rows @($fm2LivePlan.privateInputReceipt)}
foreach($pair in @(@('Guard.dll',$fm2LivePlan.guardSha256),@('Snapshot.dll',$fm2LivePlan.snapshotSha256),@('OwnerIo.dll',$fm2LivePlan.ownerIoSha256))){$path=Join-Path $e $pair[0];if((Get-ReadbackSha $path)-cne$pair[1]){throw 'Frozen helper changed'};[void][Reflection.Assembly]::LoadFrom($path)}
if((Get-ReadbackSha $fm2LivePlan.consoleHost)-cne$fm2LivePlan.consoleSha256){throw 'Canonical console host changed'}
$live=Join-Path $e live;if(Test-Path $live){throw 'ONE live invocation; retain existing attempt'};Assert-ReadbackPlain $live;[void][IO.Directory]::CreateDirectory($live)
$nonce=[Guid]::NewGuid().ToString('N');$leaseName='napo-forza2-live-'+$Go;$leaseTool='E:\Source\dbce-project-mgmt\tools\Rig-Lease.ps1';$receipt=Join-Path $env:LOCALAPPDATA ('dbce/claude-lease-'+$leaseName+'.json')
$c=@{lease=$null;leaseAttempted=$false;observing=$false;owned=$null;process=$null;snapshot=$null;clock=[Diagnostics.Stopwatch]::StartNew();gameClock=$null;last=$null;lastSeen=[DateTime]::UtcNow;lastFrame=0L;seq=0L;buttons=0;hwnd=0L;normal=$false;captureCount=0;jobSeen=@{}}
$rolePlan=@{python=$fm2LivePlan.exe;candidate=$fm2LivePlan.exe;capture=$fm2LivePlan.capture;consoleHost=$fm2LivePlan.consoleHost}
Write-Bo3Json (Join-Path $live custody.json) @{go=$Go;planSha256=$ExpectedSha256;nonce=$nonce;operatorPid=$PID;leaseName=$leaseName;receipt=$receipt;normalCloseOnly=$true}
function Lease {if(-not$c.lease-or-not(Test-Path $c.lease.path)-or(Get-Content $c.lease.path -Raw).Trim()-cne$c.lease.token){throw 'Exact named live lease lost'}}
function Pulse([bool]$Quit=$false){$c.seq++;Write-Bo3Text (Join-Path $live command.txt) ("version=1`nnonce=$nonce`nseq="+$c.seq+"`nbuttons="+$c.buttons+"`nlt=0`nrt=0`nlx=0`nly=0`nrx=0`nry=0`nquit="+[int]$Quit+"`n")}
function Guard {
 Lease;$guard=[CannonballLive]::Snapshot();Write-Bo3Json (Join-Path $live guard-latest.json) $guard
 if($guard.abortReason-or-not$guard.hooksActive-or-not$guard.hookThreadLive-or-not$guard.monitorThreadLive-or$guard.pendingRaw){throw ('Passive guard terminal/unhealthy: '+$guard.abortReason)}
 if($c.clock.Elapsed.TotalSeconds-gt600){throw 'Whole-run cleanup reserve reached'}
 if($c.owned){
  Get-Bo3JobCensus $c.owned $rolePlan $c.jobSeen (Join-Path $live job-identities.json)
  if($c.process.HasExited){throw ('Game exited before cleanup handshake: '+$c.process.ExitCode)}
  Assert-Bo3GameIdentity ([CannonballLive]::ProcessIdentity($c.owned.pid)) $c.owned ([CannonballLive]::JobPids())
  $native=Read-Bo3Status (Join-Path $live status.json) $nonce $c.owned
  if($native){$c.last=$native;if($native.frames-gt$c.lastFrame){$c.lastFrame=$native.frames;$c.lastSeen=[DateTime]::UtcNow};Write-Bo3Json (Join-Path $live parent-status.json) $native}
  if($c.gameClock.Elapsed.TotalSeconds-gt45-and([DateTime]::UtcNow-$c.lastSeen).TotalSeconds-gt15){throw 'Native Present-wrapper stopped advancing'}
  if($c.gameClock.Elapsed.TotalSeconds-gt445){throw 'Native interval wall bound reached'}
  Pulse
 }
}
function Capture([string]$Label){
 Guard;if(-not$c.last-or$c.last.frames-lt1){throw 'Native identity/output/Present-wrapper witness required'}
 $hwnd=[CannonballLive]::Window($c.owned.pid,$c.owned.birth)
 if(-not$hwnd-or($c.hwnd-and$c.hwnd-ne$hwnd)){throw 'One exact stable owned SDL HWND required'};$c.hwnd=$hwnd
 $client=[CannonballLive]::ClientSize($hwnd,$c.owned.pid);$folder=Join-Path $live ('frames-'+$Label);$before=$c.last
 Invoke-Bo3Owned $fm2LivePlan.capture @([string]$c.owned.pid,$folder,'--hwnd',('0x{0:X}'-f$hwnd),'--duration','2','--max-frames','4') $live ('capture-'+$Label) $live 15 {Guard} $false|Out-Null
 $manifest=Read-Fm2ClosedJson (Join-Path $folder capture.json) 1048576
 if($manifest.status-cne'complete'-or$manifest.process-ne$c.owned.pid-or[DateTimeOffset]::Parse($manifest.processStartedUtc).UtcTicks-ne$c.owned.birth-or$manifest.window.Handle-ne$hwnd-or$manifest.saved-lt2){throw 'R2 completion/identity differs'}
 $last=0L;$rows=@();foreach($frame in $manifest.frames){$path=Join-Path $folder $frame.File;if(-not(Test-ReadbackWithin $path $folder)-or(Get-ReadbackSha $path)-cne$frame.Sha256-or$frame.SourceWidth-lt$client[0]-or$frame.SourceHeight-lt$client[1]-or$frame.Width-ne$frame.SourceWidth-or$frame.Height-ne$frame.SourceHeight-or[long]$frame.SystemRelativeTimeTicks-le$last-or[DateTimeOffset]::Parse($frame.ArrivedUtc).UtcTicks-lt$c.owned.birth){throw 'Fresh full-raster capture differs'};$last=[long]$frame.SystemRelativeTimeTicks;$rows+=@{file=$path;sha256=$frame.Sha256;width=$frame.Width;height=$frame.Height}}
 Write-Bo3Json (Join-Path $folder readback.json) @{identity=$c.owned;hwnd=$hwnd;client=$client;nativeBefore=$before;nativeAfter=$c.last;frames=$rows;distinct=@($rows.sha256|Sort-Object -Unique).Count;ownerAcceptance=$false};$c.captureCount++
}
$actions=@{
 Preflight={if(Get-Process forza2,Forza2Launcher -ErrorAction SilentlyContinue){throw 'Existing FM2 process refused'};if([CannonballLive]::IdleSeconds()-lt180){throw 'Fresh passive idle below180s'};if((Get-ReadbackSha (Join-Path $fm2LivePlan.owner forza2.exe))-cne$fm2LivePlan.ownerExeSha256){throw 'Installed FM2 differs'}}
 Lease={if(Test-Path $receipt){throw 'Named receipt already exists'};$c.leaseAttempted=$true;&$leaseTool -Enter -Name $leaseName -IdleMinutes 3 -Purpose "FM2 native R1/R2 ONE GO$Go, private no-host normal-close-only"|Out-File (Join-Path $live lease-enter.txt);$c.lease=Get-Content $receipt -Raw|ConvertFrom-Json;Lease}
 LeaseHeld={if($c.leaseAttempted-and(Test-Path $receipt)){$maybe=Get-Content $receipt -Raw|ConvertFrom-Json;if((Test-Path $maybe.path)-and(Get-Content $maybe.path -Raw).Trim()-ceq$maybe.token){$c.lease=$maybe;return $true}};return $false}
 Observe={$c.observing=$true;[CannonballLive]::Start($fm2LivePlan.exe);Guard;Write-Bo3Json (Join-Path $live guard-start.json) ([CannonballLive]::Snapshot())}
 Snapshot={Guard;$c.snapshot=Save-ReadbackSnapshot $fm2LivePlan.ownerRoots (Join-Path $live owner-snapshot);Guard}
 Install={
  Guard;[void][IO.Directory]::CreateDirectory((Join-Path $live bin))
  foreach($row in $fm2LivePlan.products){$to=Join-Path $live ('bin/'+[IO.Path]::GetFileName($row.path));[IO.File]::Copy($row.path,$to,$false);if((Get-ReadbackSha $to)-cne$row.sha256){throw 'Private runtime copy differs'}}
  foreach($dir in @('appdata','localappdata','temp','metadata')){[void][IO.Directory]::CreateDirectory((Join-Path $live $dir))}
  $settings=@{provider_free='true';provider_free_root=("'"+$live+"'");provider_free_nonce=("'"+$nonce+"'");game_data_root=("'"+$fm2LivePlan.data+"'");user_data_root=("'"+$fm2LivePlan.user+"'");cache_root=("'"+$fm2LivePlan.cache+"'");metadata_root=("'"+(Join-Path $live metadata)+"'");gpu_plugin="'xenos'";gamertag="'dbce'";fullscreen='false';window_width='1280';window_height='720';resolution_scale='1';vsync='true';audio_mute='true';headless='true';mnk_mode='false';mnk_mouse='false';async_shader_compilation='false';gpu_allow_invalid_fetch_constants='true';log_level="'info'";log_file=("'"+(Join-Path $live native.log)+"'")}
  $settingsText=($settings.GetEnumerator()|Sort-Object Key|ForEach-Object{$_.Key+' = '+$_.Value})-join"`n"
  Write-Bo3Text (Join-Path $live bin/forza2.user.toml) ($settingsText+"`n")
  Write-Bo3Json (Join-Path $live runtime-pins.json) (Get-Bo3Rows (Join-Path $live bin));Pulse
 }
 Arm={Guard;if((Get-ReadbackSha $fm2LivePlan.exe)-cne$fm2LivePlan.candidateSha256){throw 'Private native identity differs'}}
 Launch={
  Invoke-Fm2PrivateEnvironment $live {param($environment)
   Write-Bo3Json (Join-Path $live child-environment.json) @{values=$environment;inheritedRexCvarsCleared=$true;forceRaise=$false;activateWhenShown=$false;activateWhenRaised=$false;mouseAutoCapture=$false}
   Pulse;$args=@($fm2LivePlan.exe,('--game_data_root='+$fm2LivePlan.data),('--user_data_root='+$fm2LivePlan.user),('--cache_root='+$fm2LivePlan.cache),'--provider_free=true',('--provider_free_root='+$live),('--provider_free_nonce='+$nonce))
   [CannonballLive]::MarkLaunch();$c.owned=[CannonballLive]::Launch($fm2LivePlan.exe,(Join-Path $live bin),(Join-Bo3Command $args),(Join-Path $live stdout.txt),(Join-Path $live stderr.txt),$true);$c.process=Get-Process -Id $c.owned.pid -ErrorAction Stop;$null=$c.process.Handle;$c.gameClock=[Diagnostics.Stopwatch]::StartNew();$c.lastSeen=[DateTime]::UtcNow;Write-Bo3Json (Join-Path $live game-identity.json) $c.owned
  }
 }
 Fence={$until=[DateTime]::UtcNow.AddSeconds(45);do{Guard;if($c.last-and$c.last.frames-gt1){break};[Threading.Thread]::Sleep(40)}while([DateTime]::UtcNow-lt$until);if(-not$c.last-or$c.last.frames-lt2){throw 'Native output/Present witness absent'};$modules=@($c.process.Modules|ForEach-Object FileName);Write-Bo3Json (Join-Path $live witness.json) @{identity=$c.owned;native=$c.last;modules=$modules;osInput=$false;syntheticGuestOnly=$true;physicalAcceptance=$false}}
 Steps={
  $captureAt=@(10,80,160,310,370,430);$done=@{}
  while($c.gameClock.Elapsed.TotalSeconds-lt440){Guard;$age=$c.gameClock.Elapsed.TotalSeconds;$phase=$age%60;$c.buttons=if($phase-ge40-and$phase-lt40.35){16}elseif($phase-ge50-and$phase-lt50.35){4096}else{0}
   foreach($at in $captureAt){if($age-ge$at-and-not$done.ContainsKey($at)){Capture ([string]$at);$done[$at]=$true}}
   [Threading.Thread]::Sleep(40)
  }
  $c.buttons=0;Pulse;[Threading.Thread]::Sleep(120);Guard
  if($c.captureCount-ne6){throw 'Six R2 milestones incomplete'}
  $text=Read-Bo3Text (Join-Path $live consumed.jsonl) 16777216;if(-not$text){throw 'Complete native consumed trace absent'}
  $rows=@($text.Split("`n",[StringSplitOptions]::RemoveEmptyEntries)|ForEach-Object{$_|ConvertFrom-Json -DateKind String})
  foreach($row in $rows){if($row.nonce-cne$nonce){throw 'Native trace nonce differs'}}
  $start=@($rows|Where-Object buttons -eq 16).Count;$a=@($rows|Where-Object buttons -eq 4096).Count;$neutral=@($rows|Where-Object buttons -eq 0).Count
  if($start-lt1-or$a-lt1-or$neutral-lt2-or$rows[-1].buttons-ne0-or$c.last.consumed-lt10-or$c.last.frames-lt100){throw 'Native actual Start/A/release/Present assertions incomplete'}
  Write-Bo3Json (Join-Path $live native-result.json) @{pass=$true;startRows=$start;aRows=$a;neutralRows=$neutral;consumed=$c.last.consumed;frames=$c.last.frames;captureCount=$c.captureCount;vehicleResponse=$false;physicalAcceptance=$false;settingsUi=$false;ownerAcceptance=$false}
 }
 Close={
  if($c.observing){[CannonballLive]::BeginCleanup()};$c.buttons=0
  if($c.process){$until=[DateTime]::UtcNow.AddSeconds(40);$nativeUntil=[DateTime]::UtcNow.AddSeconds(5);$closePosted=$false;while(-not$c.process.HasExited-and[DateTime]::UtcNow-lt$until){Pulse $true;Get-Bo3JobCensus $c.owned $rolePlan $c.jobSeen (Join-Path $live job-identities.json)
    if(-not$closePosted-and[DateTime]::UtcNow-gt$nativeUntil){Assert-Bo3GameIdentity ([CannonballLive]::ProcessIdentity($c.owned.pid)) $c.owned ([CannonballLive]::JobPids());$closeHwnd=[CannonballLive]::Window($c.owned.pid,$c.owned.birth);$c.process.Refresh();if(-not$closeHwnd-or$c.process.MainWindowHandle.ToInt64()-ne$closeHwnd){throw 'Exact owned SDL/main HWND required for normal WM_CLOSE'};Write-Bo3Json (Join-Path $live normal-close-request.json) @{identity=$c.owned;hwnd=$closeHwnd;message='WM_CLOSE';input=$false;activation=$false};if(-not$c.process.CloseMainWindow()){throw 'Normal owned-window close refused'};$closePosted=$true}
    [void]$c.process.WaitForExit(40)}
   if(-not$c.process.HasExited){throw 'Native normal close did not complete; NO hard kill, custody retained'};$c.normal=$c.process.ExitCode-eq0;Write-Bo3Json (Join-Path $live exit.json) @{identity=$c.owned;code=$c.process.ExitCode;normal=$c.normal;forced=$false};$c.process.Dispose()
  }
  $until=[DateTime]::UtcNow.AddSeconds(15);while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){if($c.owned){Get-Bo3JobCensus $c.owned $rolePlan $c.jobSeen (Join-Path $live job-identities.json)};[Threading.Thread]::Sleep(25)}
  if([CannonballLive]::JobPids().Length){throw 'Own job/console/helper not empty; custody retained'};[CannonballLive]::ReleaseJob()
 }
 Rollback={}
 Restore={if($c.snapshot){$check=Test-ReadbackRestored $c.snapshot;Write-Bo3Json (Join-Path $live owner-unchanged.json) $check;if(-not$check.pass){throw 'Owner state drift with no authorized owner writes; preserved for investigation'}}}
 Verify={
  $verifyExe=[CannonballLive]::ProcessIdentity($PID).image
  $verifyRoot=Invoke-Bo3Owned $verifyExe @('-NoProfile','-File',(Join-Path $PSScriptRoot Verify-Restored.ps1),'-Snapshot',(Join-Path $live owner-snapshot/manifest.json),'-ExpectedSha256',(Get-ReadbackSha (Join-Path $live owner-snapshot/manifest.json)),'-Out',(Join-Path $live independent-owner.json)) $live independent-owner $live 90 $null
  Write-Bo3Json (Join-Path $live verifier-identity.json) $verifyRoot
  $verify=(Read-Bo3Text (Join-Path $live independent-owner.json))|ConvertFrom-Json;if(-not$verify.pass){throw 'Independent owner verifier failed'};Assert-Fm2Display
  $until=[DateTime]::UtcNow.AddSeconds(10);$roles=@{python=$verifyExe;candidate=$fm2LivePlan.exe;capture=$fm2LivePlan.capture;consoleHost=$fm2LivePlan.consoleHost}
  while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){Get-Bo3JobCensus $verifyRoot $roles $c.jobSeen (Join-Path $live verifier-identities.json);[Threading.Thread]::Sleep(25)}
  if([CannonballLive]::JobPids().Length){throw 'Verifier/console tail not quiescent'}
 }
 StopObserver={if($c.observing){[CannonballLive]::Stop();$c.observing=$false;Write-Bo3Json (Join-Path $live guard-final.json) ([CannonballLive]::Snapshot())}}
 Release={if([CannonballLive]::JobPids().Length){throw 'Verifier console tail still active'};[CannonballLive]::ReleaseJob();Lease;&$leaseTool -Exit -Name $leaseName|Out-File (Join-Path $live lease-exit.txt);if(Test-Path $receipt){throw 'Named receipt remains'}}
}
$result=Invoke-CannonballLifecycle $actions (Join-Path $live lifecycle.txt)
if($result.status-ceq'PASS'-and-not$c.normal){$result.status='BLOCKED';$result.failure='Native exit nonzero'}
$result|Add-Member go $Go;$result|Add-Member normalExit $c.normal;$result|Add-Member gameForced $false;$result|Add-Member ownedStops @(Get-Bo3OwnedStopReceipts $live);$result|Add-Member jobEmpty ([CannonballLive]::JobPids().Length-eq0);$result|Add-Member seconds $c.clock.Elapsed.TotalSeconds
Write-Bo3Json (Join-Path $live qualification.json) $result
$result|ConvertTo-Json -Depth 5
if($result.status-cne'PASS'-or-not$result.released){throw 'Live qualification incomplete; exact cleanup/custody state retained'}
