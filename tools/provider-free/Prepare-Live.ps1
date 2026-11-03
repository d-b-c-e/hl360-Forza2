#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Evidence,[string]$CpuEvidence)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
$Evidence=[IO.Path]::GetFullPath($Evidence);if(-not$CpuEvidence){$CpuEvidence=$Evidence};$CpuEvidence=[IO.Path]::GetFullPath($CpuEvidence)
$cpuReceipt=Join-Path $CpuEvidence cpu-result.json;$cpu=Get-Content $cpuReceipt -Raw|ConvertFrom-Json -DateKind String
$cpuPlan=Get-Content (Join-Path $CpuEvidence cpu-plan.json) -Raw|ConvertFrom-Json -DateKind String
if($cpu.status-cne'PASS'-or-not$cpu.released-or-not$cpu.jobEmpty){throw 'Released CPU pass required'}
$source=@{root=$cpuPlan.source.root;commit=(Get-Bo3Git $cpuPlan.source.root @('rev-parse','HEAD'))};Assert-Bo3Source $source
if(Get-Bo3Git $source.root @('diff',$cpu.source,'HEAD','--','CMakeLists.txt','src','generated')){throw 'Candidate source changed; CPU build required'}
Assert-Bo3Rows $cpu.products
$inputRows=$cpu
if($CpuEvidence-ine$Evidence){
 $inputReceipt=Join-Path $Evidence private-inputs.json;$inputRows=Get-Content $inputReceipt -Raw|ConvertFrom-Json
 if($inputRows.schema-cne'fm2.private-inputs@1'-or-not$inputRows.pass-or-not$inputRows.released-or$inputRows.cpuSha256-cne(Get-ReadbackSha $cpuReceipt)){throw 'Fresh released private-input receipt required'}
}
Assert-Bo3Rows $inputRows.dataRows;Assert-Bo3Rows $inputRows.userRows;Assert-Bo3Rows $inputRows.cacheRows
foreach($kind in @('data','user','cache')){foreach($row in $inputRows.($kind+'Rows')){if(-not(Test-ReadbackWithin $row.path (Join-Path $Evidence $kind))){throw 'Private input row escaped its exact sibling root'}}}
$capture='E:\Source\game-modding\_toolkits\dbce-wheel-mod-toolkit\tools\window-capture\bin\Release\net8.0-windows10.0.22621.0\dbce-window-capture.exe'
if((Get-ReadbackSha $capture)-cne'6C4558042FAF95C54DEEF04A78719B95FF62D3CFC62858DFCA761AEDC7499EF4'-or(Get-ReadbackSha ([IO.Path]::ChangeExtension($capture,'dll')))-cne'C389845B534811A3E477F146EAB9502BC34DF7A9A6C1BD449FC16A6B79EA4976'){throw 'Qualified WGC capture bytes differ'}
$live=Join-Path $Evidence live;$console=Join-Path ([Environment]::GetFolderPath('System')) conhost.exe
$auditPath=Join-Path $Evidence host-surface-audit.json
$audit=Get-Content -LiteralPath $auditPath -Raw|ConvertFrom-Json
if(-not$audit.gatePass-or$audit.unresolved-ne0){throw 'Complete offline host-surface resolution required; runtime witnesses remain unrun'}
$resolutionPath=Join-Path $Evidence host-surface-resolution.json
$resolution=Get-Content -LiteralPath $resolutionPath -Raw|ConvertFrom-Json
$hostRows=@($audit.imports)+@($resolution.resolutions|ForEach-Object{$_.support})
$hostRows=@($hostRows|Group-Object path|ForEach-Object{$_.Group[0]})
$hostRows+=@($auditPath,$resolutionPath|ForEach-Object{@{path=$_;sha256=(Get-ReadbackSha $_)}})
Assert-Bo3Rows $hostRows
$plan=[ordered]@{schema='fm2.live-plan@1';source=$source;evidence=$Evidence;exe=(Join-Path $live bin/forza2.exe);candidate=(Join-Path $cpuPlan.build forza2.exe);candidateSha256=(Get-ReadbackSha (Join-Path $cpuPlan.build forza2.exe));products=$cpu.products;dataRows=$cpu.dataRows;userRows=$cpu.userRows;cacheRows=$cpu.cacheRows;data=(Join-Path $Evidence data);user=(Join-Path $Evidence user);cache=(Join-Path $Evidence cache);cpuSha256=(Get-ReadbackSha $cpuReceipt);guardSha256=$cpu.guardSha256;snapshotSha256=$cpu.snapshotSha256;ownerIoSha256=$cpu.ownerIoSha256;capture=$capture;captureRows=(Get-Bo3Rows (Split-Path $capture));consoleHost=$console;consoleSha256=(Get-ReadbackSha $console);sourcePins=(Get-Bo3Rows $PSScriptRoot);owner=$cpuPlan.owner;ownerExeSha256=$cpuPlan.ownerExeSha256;ownerRoots=@(@{path=$cpuPlan.owner;kind='directory'},@{path='C:\Users\antho\Documents\forza2';kind='directory'});gameSeconds=440;totalSeconds=720;cleanupReserveSeconds=120;captureCount=6;captureSeconds=2;normalCloseOnly=$true;install=$false;publicPush=$false;ownerWrite=$false;ownerAcceptance=$false;input='native private pad file; isolated controller0, no host drivers, no OS input';output='one-way isolated input latch, no SDL/XInput drivers, silent guest-audio ACK without host backend,40 native network exports fenced';assertion='native actual consumed Start/A/release and Present-wrapper progress, six exact-HWND WGC milestones; no driving/physical/settings UI claim'}
$plan.hostSurfacePins=$hostRows
$plan.cpuReceiptPath=$cpuReceipt;$plan.cpuSha256=Get-ReadbackSha $cpuReceipt
$plan.dataRows=$inputRows.dataRows;$plan.userRows=$inputRows.userRows;$plan.cacheRows=$inputRows.cacheRows
if($inputReceipt){$plan.privateInputReceipt=@{path=$inputReceipt;sha256=(Get-ReadbackSha $inputReceipt)}}
$plan.environment='private APPDATA/LOCALAPPDATA/TEMP/TMP; inherited REX_ cvars cleared child-locally; SDL force raise/activate shown/activate raised/mouse autocapture all0; parent restored in finally'
$path=Join-Path $Evidence live-plan.json;if(Test-Path $path){throw 'Fresh frozen live plan required'}
[IO.File]::WriteAllText($path,(($plan|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
@{path=$path;sha256=(Get-ReadbackSha $path);source=$source.commit;candidate=$plan.candidateSha256;gameSeconds=440;totalSeconds=720;normalCloseOnly=$true;install=$false}|ConvertTo-Json
