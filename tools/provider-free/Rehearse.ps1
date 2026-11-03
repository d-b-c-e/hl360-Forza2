#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Evidence)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
. (Join-Path $PSScriptRoot Lifecycle.ps1)
[void][Reflection.Assembly]::LoadFrom((Join-Path $Evidence Guard.dll));[void][Reflection.Assembly]::LoadFrom((Join-Path $Evidence Snapshot.dll))
[void][Reflection.Assembly]::LoadFrom((Join-Path $Evidence OwnerIo.dll))
$e=Join-Path $Evidence rehearsal;if(Test-Path -LiteralPath $e){throw 'Fresh rehearsal required'};[void][IO.Directory]::CreateDirectory($e)
$checks=0
function Check([bool]$Value,[string]$Why){$script:checks++;if(-not$Value){throw $Why}}
foreach($i in 0..2){Check ([CannonballLive]::ExplainReset($i,0,0,90000,$true)) 'First three zero-LL startup resets'}
foreach($args in @(@(3,0,0,1,$true),@(0,1,0,1,$true),@(0,0,1,1,$true),@(0,0,0,90001,$true),@(0,0,0,1,$false))){Check (-not[CannonballLive]::ExplainReset($args[0],$args[1],$args[2],$args[3],$args[4])) 'Raw reset refusal'}
Check ([CannonballLive]::ForegroundAllowed('initial','initial','',$false)) 'Fixed baseline allowed'
Check ([CannonballLive]::ForegroundAllowed('initial','game','',$true)) 'One natural exact-owned transition allowed'
Check (-not[CannonballLive]::ForegroundAllowed('initial','foreign','game',$false)) 'Foreign foreground refused'
Check (-not[CannonballLive]::ForegroundAllowed('initial','initial','game',$false)) 'Return to initial after owned activation refused'
$atomic=Join-Path $e atomic.txt;Write-Bo3Text $atomic "first`n"
$held=[IO.FileStream]::new($atomic,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite-bor[IO.FileShare]::Delete))
try{Write-Bo3Text $atomic "second`n";Check ((Read-Bo3Text $atomic)-ceq"second`n") 'Parent replace/read with held shared-delete reader'}finally{$held.Dispose()}
[IO.File]::WriteAllText($atomic,'partial');Check ($null-eq(Read-Bo3Text $atomic)) 'Partial tail retryable'
Check ($null-eq(Read-Bo3Text (Join-Path $e missing))) 'Missing active file retryable'
$identity=@{pid=123;birth=639293000000000000L};$status=Join-Path $e status.json
$good=@{schema='fm2.provider-free@1';nonce='0123456789abcdef0123456789abcdef';pid=123;birthFileTime=134381768000000000L;noHost=$true;controllers=0;inputSystems=1;networkBlocked=$true;audio='silent-ack';audioSystems=1;audioFailures=0;reason='';seq=1}
# FILETIME uses the explicit .NET epoch offset, not locale/date parsing.
$good.birthFileTime=$identity.birth-504911232000000000L
Write-Bo3Json $status $good;Check ($null-ne(Read-Bo3Status $status $good.nonce $identity)) 'Fresh identity accepted'
$bad=$false;try{Read-Bo3Status $status 'ffffffffffffffffffffffffffffffff' $identity|Out-Null}catch{$bad=$true};Check $bad 'Wrong nonce refused'
$good.controllers=0x2000;Write-Bo3Json $status $good;$bad=$false;try{Read-Bo3Status $status $good.nonce $identity|Out-Null}catch{$bad=$true};Check $bad 'Controller subsystem witness refused'
$owner=Join-Path $e owner;[void][IO.Directory]::CreateDirectory($owner);$file=Join-Path $owner settings.bin
[IO.File]::WriteAllBytes($file,[byte[]](0,1,255,10));$time=[DateTime]::new(638700000001234567L,[DateTimeKind]::Utc)
[IO.File]::SetCreationTimeUtc($file,$time);[IO.File]::SetLastWriteTimeUtc($file,$time.AddTicks(111));[IO.File]::SetAttributes($file,([IO.FileAttributes]::Hidden-bor[IO.FileAttributes]::Archive))
[IO.Directory]::SetCreationTimeUtc($owner,$time.AddTicks(222));[IO.Directory]::SetLastWriteTimeUtc($owner,$time.AddTicks(333))
Add-Type -Path (Join-Path $PSScriptRoot SparseFixture.cs)
$sparse=Join-Path $owner Partition.img;[Bo3SparseFixture]::Create($sparse)
$emptySparse=Join-Path $owner ZeroPartition.img;[IO.File]::WriteAllBytes($emptySparse,[byte[]]::new(0));[Bo3OwnerIo]::SetSparse($emptySparse,$true)
$stream=[IO.FileStream]::new($emptySparse,[IO.FileMode]::Open,[IO.FileAccess]::Write);try{$stream.SetLength(2MB)}finally{$stream.Dispose()}
$ordinary=Join-Path $owner ordinary.bin;[IO.File]::WriteAllBytes($ordinary,[byte[]](4,5,6))
$snap=Save-ReadbackSnapshot @(@{path=$owner;kind='directory'},@{path=(Join-Path $e absent);kind='directory'}) (Join-Path $e snapshot)
Check (Test-ReadbackRestored $snap).pass 'Pristine fixture snapshot'
[IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal)
[IO.File]::WriteAllText($file,'changed');[IO.File]::WriteAllText((Join-Path $owner new.txt),'extra');[void][IO.Directory]::CreateDirectory((Join-Path $e absent))
[IO.File]::WriteAllText($sparse,'changed sparse contents')
[IO.File]::WriteAllText($emptySparse,'changed empty sparse contents');[Bo3OwnerIo]::SetSparse($ordinary,$true)
Check (-not(Test-ReadbackRestored $snap).pass) 'Changed fixture rejected'
Restore-ReadbackSnapshot $snap (Join-Path $e after);Check (Test-ReadbackRestored $snap).pass 'Full bytes/raw attrs/file+directory creation/write/presence restored'
$manifest=Join-Path $e snapshot/manifest.json
$pwsh=(Get-Process -Id $PID).Path
$bo3BudgetFixture=@{clock=[Diagnostics.Stopwatch]::StartNew();workSeconds=20}
Invoke-Bo3Owned $pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot Verify-Restored.ps1),'-Snapshot',$manifest,'-ExpectedSha256',(Get-ReadbackSha $manifest),'-Out',(Join-Path $e independent.json)) $e independent $e 20 {Assert-Bo3Budget $bo3BudgetFixture}|Out-Null
Check ($bo3BudgetFixture.clock.Elapsed.TotalSeconds-lt20) 'Real child callback retains explicit whole budget despite helper-local process/clock'
$bad=$false;try{Assert-Bo3Budget $null}catch{$bad=$true};Check $bad 'Missing budget terminal'
$bad=$false;try{Assert-Bo3Budget @{clock=[Diagnostics.Stopwatch]::StartNew();workSeconds=0}}catch{$bad=$true};Check $bad 'Invalid zero budget terminal'
$bad=$false;try{Assert-Bo3Budget @{clock=[Diagnostics.Stopwatch]::StartNew();workSeconds=0.00000001}}catch{$bad=$true};Check $bad 'Expired positive budget terminal'
Check ((Get-Content (Join-Path $e independent.json) -Raw|ConvertFrom-Json).pass) 'Separate process numeric verifier'
Check ([CannonballLive]::JobPids().Length-eq0) 'Suspended job helper fully quiescent'
[CannonballLive]::ReleaseJob()
$events=[Collections.Generic.List[string]]::new();$actions=@{};foreach($name in @('Preflight','Lease','Observe','Snapshot','Install','Arm','Launch','Fence','Steps','Close','Rollback','Restore','Verify','StopObserver','Release')){$n=$name;$actions[$n]={$events.Add($n)}.GetNewClosure()}
$result=Invoke-CannonballLifecycle $actions (Join-Path $e lifecycle-pass.txt);Check ($result.status-eq'PASS'-and$result.released) 'Real lifecycle callbacks pass'
$actions.Steps={throw 'inert planned failure'};$result=Invoke-CannonballLifecycle $actions (Join-Path $e lifecycle-failure.txt);Check ($result.status-eq'BLOCKED'-and$result.released) 'Terminal failure still closes/restores/verifies/stops/releases'
$r=@{pass=$true;checks=$checks;game=$false;hooks=$false;input=$false;renderer=$false;ownerState=$false;guardSourceSha256=(Get-ReadbackSha (Join-Path $PSScriptRoot CannonballLive.cs));guardSha256=(Get-ReadbackSha (Join-Path $Evidence Guard.dll));snapshotSourceSha256=(Get-ReadbackSha (Join-Path $PSScriptRoot Snapshot.cs));snapshotSha256=(Get-ReadbackSha (Join-Path $Evidence Snapshot.dll));sparseRestore='existing sparse file overwritten/length restored, raw attrs + SHA verified';independent=(Get-Content (Join-Path $e independent.json) -Raw|ConvertFrom-Json)}
Write-Bo3Json (Join-Path $e result.json) $r;$r|ConvertTo-Json -Depth 6
