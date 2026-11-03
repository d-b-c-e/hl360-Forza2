#Requires -Version 7.3
param([Parameter(Mandatory)][string]$Evidence,[Parameter(Mandatory)][string]$CheapA,[Parameter(Mandatory)][string]$CheapB)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
. (Join-Path $PSScriptRoot Environment.ps1)
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ../..));$Evidence=[IO.Path]::GetFullPath($Evidence)
if(-not(Test-ReadbackWithin $Evidence (Join-Path $root _local/provider-free))-or(Test-Path $Evidence)){throw 'Fresh project CPU plan required'}
$source=@{root=$root;commit=(Get-Bo3Git $root @('rev-parse','HEAD'))};Assert-Bo3Source $source
$cheap=@();foreach($dir in @($CheapA,$CheapB)){$p=Join-Path $dir result.json;$r=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -DateKind String;if(-not$r.pass-or$r.game-or$r.hooks-or$r.device-or$r.owner-or$r.lease){throw 'Complete scratch suite required twice'};Assert-Bo3Rows $r.sourcePins;Assert-Bo3Rows $r.sdkPins;$cheap+=@{path=$p;sha256=(Get-ReadbackSha $p);result=$r}}
$canonicalA=@($cheap[0].result.sourcePins|Sort-Object path|ForEach-Object{$_.path+'|'+$_.sha256})-join"`n";$canonicalB=@($cheap[1].result.sourcePins|Sort-Object path|ForEach-Object{$_.path+'|'+$_.sha256})-join"`n"
if($canonicalA-cne$canonicalB){throw 'Scratch suite pins differ'}
$derived=@($cheap[0].result.toolchain.pins)+@($cheap[1].result.toolchain.pins)
if(-not$cheap[0].result.toolchain.pass-or-not$cheap[1].result.toolchain.pass-or-not$cheap[0].result.toolchain.dryRunNoGenerator-or-not$cheap[1].result.toolchain.dryRunNoGenerator){throw 'Actual toolchain smoke/dry-run required twice'}
$derivedTools=@(foreach($group in ($derived|Group-Object path)){$first=$group.Group[0];if(@($group.Group.sha256|Sort-Object -Unique).Count-ne1){throw 'Observed tool image drift'};@{path=$first.path;sha256=$first.sha256;roles=@($group.Group.roles|ForEach-Object{$_}|Sort-Object -Unique);identities=@($group.Group.identities|ForEach-Object{$_})}})
Assert-Bo3Rows $derivedTools
$sdk='E:\Source\game-modding\dbce-mods-forza-motorsport-2\_sdk\win-amd64'
$tools=@{pwsh=(Get-Process -Id $PID).Path;cmake='C:\Program Files\CMake\bin\cmake.exe';clang='C:\Program Files\LLVM\bin\clang.exe';clangxx='C:\Program Files\LLVM\bin\clang++.exe';ninja='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe';readobj='C:\Program Files\LLVM\bin\llvm-readobj.exe'}
$tools.lld='C:\Program Files\LLVM\bin\lld-link.exe';$tools.cmd=$env:ComSpec;$tools.console=Join-Path ([Environment]::GetFolderPath('System')) conhost.exe
$msvcTools=Get-Fm2MsvcTools $CheapB;foreach($toolName in $msvcTools.Keys){$tools[$toolName]=$msvcTools[$toolName]}
$pins=@(foreach($v in $tools.Values){Assert-ReadbackPlain $v;@{path=$v;bytes=(Get-Item -LiteralPath $v).Length;sha256=(Get-ReadbackSha $v)}})
$hostAudit=@{reader='E:\Source\dbce-project-mgmt\tools\desktop-routes\Read-HostSurfaceImports.ps1';catalog='E:\Source\dbce-project-mgmt\tools\desktop-routes\host-surface-imports.json'}
$hostAudit.pins=@(foreach($v in @($hostAudit.reader,$hostAudit.catalog)){@{path=$v;sha256=(Get-ReadbackSha $v)}})
$owner='E:\Source\tools\launchbox\Launchbox-Racing\Games\Windows\Forza Motorsport 2 (Native)'
if((Get-ReadbackSha (Join-Path $owner forza2.exe))-cne'95E74E3DCD4EA5AB3A50A4DD0363561DCD1211D4BA05C0D19CEC9F2015A69A50'){throw 'Installed native identity changed'}
Assert-ReadbackPlain $Evidence;[void][IO.Directory]::CreateDirectory($Evidence)
$plan=[ordered]@{schema='fm2.cpu-plan@1';source=$source;sdk=$sdk;sdkPins=(Get-Bo3Rows $sdk);tools=$tools;toolPins=$pins;owner=$owner;ownerExeSha256=(Get-ReadbackSha (Join-Path $owner forza2.exe));ownerProfile='C:\Users\antho\Documents\forza2\profiles\dbce';ownerCache='C:\Users\antho\Documents\forza2\cache';evidence=$Evidence;build=(Join-Path $Evidence build);totalSeconds=1800;cleanupReserveSeconds=90;jobs=2;sourcePins=(Get-Bo3Rows $PSScriptRoot);cheap=$cheap;game=$false;input=$false;ownerWrite=$false;install=$false;publicPush=$false;actions=@('verify+clone owned disc against genuine2344-file manifest and clone dbce profile/cache','CMake native forza2 only, existing generated code, pinned SDK0.10.0, jobs2','complete product/runtime/generated identity and PE import receipt; no launch')}
$plan.hostAudit=$hostAudit
$plan.derivedTools=$derivedTools
[IO.File]::WriteAllText((Join-Path $Evidence cpu-plan.json),(($plan|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
@{path=(Join-Path $Evidence cpu-plan.json);sha256=(Get-ReadbackSha (Join-Path $Evidence cpu-plan.json));source=$source.commit;sdkFiles=$plan.sdkPins.Count;totalSeconds=$plan.totalSeconds;jobs=2;game=$false}|ConvertTo-Json
