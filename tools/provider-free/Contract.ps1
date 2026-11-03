# Pure import; native helpers are loaded only by an explicitly bounded runner.
function Read-Fm2Plan([string]$Path,[string]$Sha256,[string]$Schema){
 if((Get-ReadbackSha $Path)-cne$Sha256){throw 'Frozen plan hash differs'}
 $value=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -DateKind String
 if($value.schema-cne$Schema-or$value.install-isnot[bool]-or$value.install-or$value.publicPush-isnot[bool]-or$value.publicPush){throw 'Plan scope differs'}
 if($Schema-ceq'fm2.cpu-plan@1'){
  if($value.totalSeconds-ne1800-or$value.cleanupReserveSeconds-ne90-or$value.jobs-ne2-or$value.game-or$value.input-or$value.ownerWrite){throw 'CPU bounds differ'}
 }elseif($Schema-ceq'fm2.live-plan@1'){
  if($value.totalSeconds-ne720-or$value.cleanupReserveSeconds-ne120-or$value.gameSeconds-ne440-or$value.captureCount-ne6-or$value.captureSeconds-ne2){throw 'Live bounds differ'}
 }else{throw 'Unknown plan schema'}
 return $value
}
function Write-Bo3Text([string]$Path,[string]$Text){
 $tmp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($tmp,$Text,[Text.UTF8Encoding]::new($false));[OutRunSnapshot]::Publish($tmp,$Path)
}
function Write-Bo3Json([string]$Path,$Value){Write-Bo3Text $Path (($Value|ConvertTo-Json -Depth 18)+"`n")}
function Read-Bo3Text([string]$Path,[int]$Limit=65536){
 $s=$null;$r=$null
 try{$s=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite-bor[IO.FileShare]::Delete));if($s.Length-gt$Limit){throw 'Active file budget exceeded'};$r=[IO.StreamReader]::new($s,[Text.UTF8Encoding]::new($false),$false);$text=$r.ReadToEnd();if(-not$text.EndsWith("`n")){return $null};return $text}
 catch [IO.IOException]{return $null}finally{if($r){$r.Dispose()}elseif($s){$s.Dispose()}}
}
function Read-Bo3Status([string]$Path,[string]$Nonce,$Identity){
 $text=Read-Bo3Text $Path;if($null-eq$text){return $null}
 try{$s=$text|ConvertFrom-Json -DateKind String}catch{return $null}
 if($s.schema-cne'fm2.provider-free@1'-or$s.nonce-cne$Nonce-or$s.pid-ne$Identity.pid-or[long]$s.birthFileTime-ne($Identity.birth-504911232000000000L)){throw 'Status identity differs'}
 if(-not$s.noHost-or$s.controllers-ne0-or$s.inputSystems-ne1-or-not$s.networkBlocked-or$s.audio-cne'silent-ack'-or$s.audioSystems-ne1-or$s.audioFailures-or$s.reason){throw ('Native output fence failed: '+$s.reason)}
 return $s
}
function Get-Bo3Rows([string]$Root){@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|Sort-Object FullName|ForEach-Object{Assert-ReadbackPlain $_.FullName;@{path=$_.FullName;bytes=$_.Length;sha256=(Get-ReadbackSha $_.FullName)}})}
function Assert-Bo3Rows($Rows){foreach($r in $Rows){Assert-ReadbackPlain $r.path;if((Get-ReadbackSha $r.path)-cne$r.sha256){throw ('Pinned input changed: '+$r.path)}}}
function Get-Bo3Git([string]$Root,[string[]]$Arguments){$s=@(& git -C $Root @Arguments);if($LASTEXITCODE){throw 'Git identity failed'};($s-join"`n").Trim()}
function Assert-Bo3Source($Repo){if((Get-Bo3Git $Repo.root @('rev-parse','HEAD'))-cne$Repo.commit-or(Get-Bo3Git $Repo.root @('status','--porcelain=v1'))){throw ('Source drift: '+$Repo.root)}}
function Assert-Bo3Budget($Bounds){if($null-eq$Bounds-or$Bounds.clock-isnot[Diagnostics.Stopwatch]-or$Bounds.workSeconds-le0){throw 'Missing/invalid explicit CPU budget'};if($Bounds.clock.Elapsed.TotalSeconds-gt$Bounds.workSeconds){throw 'CPU cleanup reserve reached'}}
function Assert-Bo3GameIdentity($Observed,$HeldRoot,[int[]]$JobPids){
 if($Observed.pid-ne$HeldRoot.pid-or$Observed.birth-ne$HeldRoot.birth-or$Observed.image-ine$HeldRoot.image-or$HeldRoot.pid-notin$JobPids){throw 'Game PID/birth/image/job differs'}
}
function Get-Bo3OwnedStopReceipts([string]$Evidence){@(Get-ChildItem -LiteralPath $Evidence -File -Filter '*.before-owned-termination.json'|ForEach-Object{@{path=$_.FullName;sha256=(Get-ReadbackSha $_.FullName)}})}
function Get-Bo3JobIdentities {
 foreach($childId in @([CannonballLive]::JobPids())){
  try{[CannonballLive]::ProcessIdentity($childId)}catch{
   $still=Get-Process -Id $childId -ErrorAction SilentlyContinue
   if($still){try{if(-not$still.HasExited){throw}}finally{$still.Dispose()}}
  }
 }
}
function Get-Bo3JobCensus($RootIdentity,$RolePlan,[hashtable]$Seen,[string]$EvidenceFile){
 # JobPolicy.ps1 is remi's unchanged cbf04107 classifier. Only query handles
 # already returned from this fresh job, and persist identity BEFORE refusal.
 foreach($childId in @([CannonballLive]::JobPids())){
  try{$id=[CannonballLive]::ProcessIdentity($childId)}catch{if(Get-Process -Id $childId -ErrorAction SilentlyContinue){throw};continue}
  $role=Get-OwnedJobRole $id $RootIdentity $RolePlan;$key=[string]$id.pid+':'+[string]$id.birth
  if(-not$Seen.ContainsKey($key)){$Seen[$key]=@{pid=$id.pid;birth=$id.birth;image=$id.image;role=$role};Write-Bo3Json $EvidenceFile @($Seen.Values)}
  if($role-notin@('root','game','capture','console-host')){throw ('Unadmitted own-job identity: '+$role+' '+$id.image)}
 }
}
function Join-Bo3Command([string[]]$Words){
 (@(foreach($word in $Words){$b=[Text.StringBuilder]::new('"');$slashes=0;foreach($c in $word.ToCharArray()){if($c-eq'\'){$slashes++;continue};if($c-eq'"'){[void]$b.Append(('\'*(2*$slashes+1)))}else{[void]$b.Append(('\'*$slashes))};$slashes=0;[void]$b.Append($c)};[void]$b.Append(('\'*(2*$slashes)));[void]$b.Append('"');$b.ToString()})-join' ')
}
function Invoke-Bo3Owned([string]$Exe,[string[]]$Arguments,[string]$Cwd,[string]$Label,[string]$Evidence,[int]$Seconds,[scriptblock]$Tick,[bool]$KillWholeJobOnFailure=$true,[int]$PollMs=40){
 if($PollMs-lt5-or$PollMs-gt200){throw 'Owned helper polling bound differs'}
 $id=[CannonballLive]::Launch($Exe,$Cwd,(Join-Bo3Command (@($Exe)+$Arguments)),(Join-Path $Evidence ($Label+'.stdout.txt')),(Join-Path $Evidence ($Label+'.stderr.txt')),$false)
 Write-Bo3Json (Join-Path $Evidence ($Label+'.identity.json')) $id
 $p=Get-Process -Id $id.pid -ErrorAction Stop;$null=$p.Handle;$clock=[Diagnostics.Stopwatch]::StartNew();$firstFailure=$null
 try{while(-not$p.WaitForExit($PollMs)){if($Tick){&$Tick};if($clock.Elapsed.TotalSeconds-gt$Seconds){throw ('Owned helper deadline: '+$Label)}};if($Tick){&$Tick};if($p.ExitCode){throw ('Owned helper failed: '+$Label+' exit '+$p.ExitCode)};return $id}
 catch{$firstFailure=$_.Exception.Message;throw}
 finally{try{if(-not$p.HasExited){$census=@(Get-Bo3JobIdentities);Write-Bo3Json (Join-Path $Evidence ($Label+'.before-owned-termination.json')) @{scope=$(if($KillWholeJobOnFailure){'whole-job'}else{'helper-only'});root=$id;members=$census;firstFailure=$firstFailure};if($KillWholeJobOnFailure){[CannonballLive]::KillOwned()}else{Assert-Bo3GameIdentity ([CannonballLive]::ProcessIdentity($id.pid)) $id ([CannonballLive]::JobPids());$p.Kill()};if(-not$p.WaitForExit(5000)){throw 'Owned process termination incomplete'}}}catch{if($firstFailure){Write-Bo3Json (Join-Path $Evidence ($Label+'.cleanup-error.json')) @{firstFailure=$firstFailure;cleanupFailure=$_.Exception.Message};throw $firstFailure};throw}finally{$p.Dispose()}}
}
