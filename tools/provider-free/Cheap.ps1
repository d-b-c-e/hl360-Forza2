#Requires -Version 7.3
# Complete scratch-only admission. No rig lease, game, renderer, hooks,
# physical input/device enumeration, owner files or SDK/game build.
param([Parameter(Mandatory)][string]$Evidence)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot Owner-State.ps1)
. (Join-Path $PSScriptRoot Contract.ps1)
. (Join-Path $PSScriptRoot JobPolicy.ps1)
. (Join-Path $PSScriptRoot Environment.ps1)
. (Join-Path $PSScriptRoot Data.ps1)
. (Join-Path $PSScriptRoot Toolchain.ps1)
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ../..));$Evidence=[IO.Path]::GetFullPath($Evidence)
if(-not(Test-ReadbackWithin $Evidence (Join-Path $root _local/provider-free))-or(Test-Path $Evidence)){throw 'Fresh project scratch required'}
Assert-ReadbackPlain $Evidence;[void][IO.Directory]::CreateDirectory($Evidence)
$r=[ordered]@{pass=$false;startedUtc=[DateTime]::UtcNow.ToString('o');runnerPid=$PID;game=$false;hooks=$false;device=$false;owner=$false;lease=$false;failure=$null}
$r.sourcePins=@(Get-Bo3Rows $PSScriptRoot)+@(Get-Bo3Rows (Join-Path $root src) | Where-Object path -match 'provider_free|scripted_input|frame_stats|forza2_app')+@(Get-Bo3Rows (Join-Path $root tests/provider_free))
foreach($file in @('CMakeLists.txt','generated/rexglue.cmake')){$r.sourcePins+=@{path=(Join-Path $root $file);bytes=(Get-Item (Join-Path $root $file)).Length;sha256=(Get-ReadbackSha (Join-Path $root $file))}}
try{
 $environmentPrevious=@{SDL_FORCE_RAISEWINDOW=[Environment]::GetEnvironmentVariable('SDL_FORCE_RAISEWINDOW','Process');REX_FM2_FIXTURE_SENTINEL=[Environment]::GetEnvironmentVariable('REX_FM2_FIXTURE_SENTINEL','Process')}
 try{
  $env:SDL_FORCE_RAISEWINDOW='1';$env:REX_FM2_FIXTURE_SENTINEL='fixture'
  $environmentCase=@{calls=0}
  Invoke-Fm2PrivateEnvironment $Evidence {param($values);if($env:SDL_FORCE_RAISEWINDOW-cne'0'-or$env:SDL_WINDOW_ACTIVATE_WHEN_SHOWN-cne'0'-or$env:SDL_WINDOW_ACTIVATE_WHEN_RAISED-cne'0'-or$env:SDL_MOUSE_AUTO_CAPTURE-cne'0'-or$env:REX_FM2_FIXTURE_SENTINEL-or$env:APPDATA-cne(Join-Path $Evidence appdata)){throw 'Private child environment differs'};$environmentCase.calls++}
  $environmentRefused=$false;try{Invoke-Fm2PrivateEnvironment $Evidence {throw 'environment fixture failure'}}catch{$environmentRefused=$_.Exception.Message-ceq'environment fixture failure'}
  if(-not$environmentRefused-or$environmentCase.calls-ne1-or$env:SDL_FORCE_RAISEWINDOW-cne'1'-or$env:REX_FM2_FIXTURE_SENTINEL-cne'fixture'){throw 'Private environment restore failed'};$r.privateEnvironmentCases=3
 }finally{foreach($key in $environmentPrevious.Keys){[Environment]::SetEnvironmentVariable($key,$environmentPrevious[$key],'Process')}}
 foreach($row in @(@('CannonballLive.cs','Guard.dll'),@('Snapshot.cs','Snapshot.dll'),@('OwnerIo.cs','OwnerIo.dll'))){$out=Join-Path $Evidence $row[1];Add-Type -Path (Join-Path $PSScriptRoot $row[0]) -OutputAssembly $out;[void][Reflection.Assembly]::LoadFrom($out)}
 $pwsh=[CannonballLive]::ProcessIdentity($PID).image
 foreach($kind in @('cpu','live')){
  $fixture=if($kind-ceq'cpu'){@{schema='fm2.cpu-plan@1';totalSeconds=1800;cleanupReserveSeconds=90;jobs=2;game=$false;input=$false;ownerWrite=$false;install=$false;publicPush=$false}}else{@{schema='fm2.live-plan@1';totalSeconds=720;cleanupReserveSeconds=120;gameSeconds=440;captureCount=6;captureSeconds=2;install=$false;publicPush=$false}}
  $fixturePath=Join-Path $Evidence ($kind+'-plan-fixture.json');Write-Bo3Json $fixturePath $fixture
  $runner=if($kind-ceq'cpu'){'Build.ps1'}else{'Run.ps1'}
  Invoke-Bo3Owned $pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot $runner),'-Plan',$fixturePath,'-ExpectedSha256',(Get-ReadbackSha $fixturePath),'-Go','504092','-CheckPlanOnly') $root ($kind+'-scope-positive') $Evidence 15 $null|Out-Null
  $scope=(Read-Bo3Text (Join-Path $Evidence ($kind+'-scope-positive.stdout.txt')))|ConvertFrom-Json
  if(-not$scope.scopePass-or$scope.planType-cne'System.Management.Automation.PSCustomObject'-or$scope.game-or$scope.lease-or$scope.hooks-or$scope.owner){throw 'Actual runner typed-plan regression failed'}
  $fixture.totalSeconds--;Write-Bo3Json $fixturePath $fixture
  $refused=$false;try{Invoke-Bo3Owned $pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot $runner),'-Plan',$fixturePath,'-ExpectedSha256',(Get-ReadbackSha $fixturePath),'-Go','504092','-CheckPlanOnly') $root ($kind+'-scope-negative') $Evidence 15 $null|Out-Null}catch{$refused=$_.Exception.Message-eq('Owned helper failed: '+$kind+'-scope-negative exit 1')}
  if(-not$refused){throw 'Actual runner failed to refuse wrong bounds'}
 }
 $r.actualRunnerScopeCases=4
 $copySource=Join-Path $Evidence copy-source;[void][IO.Directory]::CreateDirectory((Join-Path $copySource empty));[IO.File]::WriteAllText((Join-Path $copySource one.txt),'fixture')
 $ticks=@{count=0};$copyRows=@(Copy-Fm2Tree $copySource (Join-Path $Evidence copy-destination) {$ticks.count++})
 if($copyRows.Count-ne1-or$ticks.count-ne1-or-not(Test-Path (Join-Path $Evidence copy-destination/empty))){throw 'Actual data clone path failed'}
 $fixtureRows=@(0..2343|ForEach-Object{@{relative=('file{0:D4}'-f$_);sha256=$copyRows[0].sha256;bytes=7}})
 $discManifest=Join-Path $Evidence disc-contract.txt;$discText=($fixtureRows|ForEach-Object{$_.sha256.ToLowerInvariant()+' 7 '+$_.relative})-join"`n"
 [IO.File]::WriteAllText($discManifest,($discText+"`n"+('0'*64)+' 7 file0000'+"`n"))
 if(-not(Test-Fm2Disc $fixtureRows $discManifest).pass){throw 'Real disc manifest alternatives failed'}
 $fixtureRows[0].sha256='F'*64;$refused=$false;try{Test-Fm2Disc $fixtureRows $discManifest|Out-Null}catch{$refused=$true};if(-not$refused){throw 'Real disc verifier accepted changed bytes'};$r.dataContractCases=3
 foreach($psFile in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1'){$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($psFile.FullName,[ref]$tokens,[ref]$parseErrors);if($parseErrors){throw ('PowerShell parse error: '+$psFile.Name+' '+($parseErrors.Message-join';'))}}
 Invoke-Bo3Owned $pwsh @('-NoProfile','-File',(Join-Path $PSScriptRoot Rehearse.ps1),'-Evidence',$Evidence) $root rehearsal $Evidence 60 $null|Out-Null
 $clang='C:\Users\antho\.cache\bo3-windeps\llvm-mingw\bin\x86_64-w64-mingw32-clang.exe';$exe=Join-Path $Evidence io-test.exe
 Invoke-Bo3Owned $clang @('-std=c11','-O2','-Wall','-Wextra','-Isrc','tests/provider_free/test_io.c','src/provider_free_io.c','-o',$exe) $root io-compile $Evidence 20 $null|Out-Null
 Invoke-Bo3Owned $exe @((Join-Path $Evidence io-fixture)) $root io-test $Evidence 20 $null|Out-Null
 $consoleExe=Join-Path $Evidence inert-console.exe
 Invoke-Bo3Owned $clang @('-std=c11','-O2','tests/provider_free/test_console.c','-o',$consoleExe) $root console-compile $Evidence 20 $null|Out-Null
 $until=[DateTime]::UtcNow.AddSeconds(5);while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){[Threading.Thread]::Sleep(20)}
 [CannonballLive]::ReleaseJob()
 $consoleHost=Join-Path ([Environment]::GetFolderPath('System')) conhost.exe
 $consoleRoot=[CannonballLive]::Launch($consoleExe,$Evidence,(Join-Bo3Command @($consoleExe)),(Join-Path $Evidence console.stdout.txt),(Join-Path $Evidence console.stderr.txt),$false)
 $consoleProcess=Get-Process -Id $consoleRoot.pid -ErrorAction Stop;$null=$consoleProcess.Handle
 $heldFixtureRoot=$consoleRoot;$calls=@{count=0;shadowObserved=$false}
 $helperExe=Join-Path $Evidence identity-helper.exe;[IO.File]::Copy($consoleExe,$helperExe,$false)
 Invoke-Bo3Owned $helperExe @('helper') $root identity-helper $Evidence 10 {
  if($Exe-ieq$helperExe){$calls.shadowObserved=$true}
  Assert-Bo3GameIdentity ([CannonballLive]::ProcessIdentity($heldFixtureRoot.pid)) $heldFixtureRoot ([CannonballLive]::JobPids());$calls.count++
 }|Out-Null
 if($calls.count-lt1-or-not$calls.shadowObserved){throw 'Actual helper executable-shadow regression did not execute'}
 $helperStopped=$false;try{Invoke-Bo3Owned $helperExe @('helper') $root intentional-helper-only-stop $Evidence 10 {throw 'inert helper-only failure'} $false|Out-Null}catch{$helperStopped=$_.Exception.Message-eq'inert helper-only failure'}
 if(-not$helperStopped-or$consoleProcess.HasExited){throw 'Helper-only stop killed or lost unrelated owned root'};$r.helperOnlyStopPreservesRoot=$true
 $helperStop=(Read-Bo3Text (Join-Path $Evidence intentional-helper-only-stop.before-owned-termination.json))|ConvertFrom-Json
 if($helperStop.firstFailure-cne'inert helper-only failure'-or$helperStop.scope-cne'helper-only'){throw 'Cleanup masked the first refusal'};$r.firstRefusalVerbatim=$true
 foreach($n in 0..19){$label='rapid-exit-'+$n;$fast=[CannonballLive]::Launch($helperExe,$Evidence,(Join-Bo3Command @($helperExe,'fast')),(Join-Path $Evidence ($label+'.stdout.txt')),(Join-Path $Evidence ($label+'.stderr.txt')),$false);[void]@(Get-Bo3JobIdentities)}
 $r.rapidExitCensuses=20
 # Rapid roots can remain scheduled for a moment after Launch returns. Drain
 # only these fixture helpers before applying the root/console-only policy.
 $until=[DateTime]::UtcNow.AddSeconds(3)
 do{$extras=@(Get-Bo3JobIdentities|Where-Object{$_.pid-ne$consoleRoot.pid-and$_.image-ine$consoleHost});if(-not$extras.Count){break};if([DateTime]::UtcNow-gt$until){throw 'Rapid fixture helpers did not exit'};[Threading.Thread]::Sleep(10)}while($true)
 $rolePlan=@{python=$consoleExe;candidate=(Join-Path $Evidence unused-game.exe);capture=(Join-Path $Evidence unused-capture.exe);consoleHost=$consoleHost};$seen=@{};$until=[DateTime]::UtcNow.AddSeconds(8)
 try{do{Get-Bo3JobCensus $consoleRoot $rolePlan $seen (Join-Path $Evidence console-identities.json);if($consoleProcess.WaitForExit(20)-and-not[CannonballLive]::JobPids().Length){break};if($consoleProcess.HasExited){[Threading.Thread]::Sleep(20)};if([DateTime]::UtcNow-gt$until){throw 'Inert console child deadline'}}while($true);if($consoleProcess.ExitCode){throw 'Inert console exit failed'}}finally{$consoleProcess.Dispose()}
 if([CannonballLive]::JobPids().Length){throw 'Inert console job not empty'};[CannonballLive]::ReleaseJob()
 if([CannonballLive]::RetainedProcessHandles()-ne0){throw 'Own fast-exit root handles leaked'}
 $cases=@(@(@{pid=$consoleRoot.pid;birth=$consoleRoot.birth;image=$consoleExe},'root'),@(@{pid=1;birth=$consoleRoot.birth+1;image=$consoleHost},'console-host'),@(@{pid=1;birth=$consoleRoot.birth-1;image=$consoleHost},'unknown-epoch'),@(@{pid=1;birth=$consoleRoot.birth+1;image=(Join-Path $Evidence conhost.exe)},'unknown-image'),@(@{pid=$consoleRoot.pid+1;birth=$consoleRoot.birth+1;image=$consoleExe},'unknown-python'),@(@{pid=1;birth=$consoleRoot.birth+1;image=$rolePlan.capture},'capture'))
 foreach($case in $cases){if((Get-OwnedJobRole $case[0] $consoleRoot $rolePlan)-cne$case[1]){throw 'Production console policy case failed'}}
 $r.consoleIdentities=@($seen.Values);$r.jobPolicyCases=$cases.Count;$r.consoleHostSha256=Get-ReadbackSha $consoleHost
 $failed=$false;try{Invoke-Bo3Owned $pwsh @('-NoProfile','-Command','[Threading.Thread]::Sleep(1000)') $root intentional-owned-stop $Evidence 10 {throw 'inert callback failure'}|Out-Null}catch{$failed=$_.Exception.Message-eq'inert callback failure'}
 if(-not$failed-or@(Get-Bo3OwnedStopReceipts $Evidence).Count-ne2){throw 'Nested owned-stop accounting regression failed'}
 $until=[DateTime]::UtcNow.AddSeconds(5);while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){[Threading.Thread]::Sleep(20)}
 if([CannonballLive]::JobPids().Length){throw 'Inert stop not quiescent'};[CannonballLive]::ReleaseJob();$r.nestedOwnedStopAccounted=$true
 # Verify the *entire* compiled networking import set before linking real wrappers.
 $imports=@(Select-String -LiteralPath (Join-Path $root generated/default/forza2_init.cpp) -Pattern '\{ 0x[0-9A-F]+, __imp__(NetDll_\w+) \}'|ForEach-Object{$_.Matches[0].Groups[1].Value}|Sort-Object -Unique)
 $fences=@(Select-String -LiteralPath (Join-Path $root src/provider_free_network.def) -Pattern '^FM2_NET\((\w+),'|ForEach-Object{$_.Matches[0].Groups[1].Value}|Sort-Object -Unique)
 if($imports.Count-ne40-or(Compare-Object $imports $fences)){throw 'Compiled network import fence incomplete'};$r.networkImports=$imports
 $r.toolchain=Invoke-Fm2ToolchainSmoke $root $Evidence 'E:\Source\game-modding\dbce-mods-forza-motorsport-2\_sdk\win-amd64'
 $msvcTools=Get-Fm2MsvcTools $Evidence
 if($msvcTools-isnot[hashtable]-or$msvcTools.Count-ne3){throw 'Actual CPU-plan MSVC tool extraction failed'}
 foreach($name in @('link','rc','mt')){if(-not(Test-Path -LiteralPath $msvcTools[$name])-or$msvcTools[$name]-cne[IO.Path]::GetFullPath($msvcTools[$name])){throw 'Actual MSVC canonical tool path missing'}};$r.actualMsvcToolPaths=$msvcTools
 $sdk='E:\Source\game-modding\dbce-mods-forza-motorsport-2\_sdk\win-amd64'
 $r.sdkPins=@(Get-Bo3Rows (Join-Path $sdk include/rex/input)) + @('bin/rexruntime.dll','lib/rexruntime.lib','share/rexglue/rex_app.cpp','share/rexglue/windowed_app_main_sdl.cpp' | ForEach-Object {$pin=Join-Path $sdk $_;@{path=$pin;bytes=(Get-Item -LiteralPath $pin).Length;sha256=(Get-ReadbackSha $pin)}})
 Copy-Item -LiteralPath (Join-Path $sdk bin/rexruntime.dll) -Destination $Evidence
 $compiler='C:\Program Files\LLVM\bin\clang-cl.exe';$nativeExe=Join-Path $Evidence native-test.exe
 $defines=@(@('XamInputGetState','XamInputGetCapabilities','XamInputSetState','XamInputGetKeystroke')+$fences|ForEach-Object{'/D__imp__'+$_+'=Fm2Native_'+$_})
 $args=@('/nologo','/std:c++latest','/EHsc','/MD','/DWIN32','/DNOMINMAX','/DWIN32_LEAN_AND_MEAN','/DSPDLOG_COMPILED_LIB','/DSPDLOG_FMT_EXTERNAL','/DREX_HAS_D3D12=1','/clang:-msse4.1')+$defines+@(('/I'+$sdk+'/include'),'/Isrc','tests/provider_free/test_native.cpp','src/scripted_input.cpp','src/frame_stats.cpp','src/provider_free_io.c',('/Fe:'+ $nativeExe),('/Fo'+$Evidence+'\'),'/link',('/libpath:'+$sdk+'/lib'),'rexruntime.lib','fmt.lib','spdlog.lib')
 Invoke-Bo3Owned $compiler $args $root native-compile $Evidence 40 $null|Out-Null
 $syntaxArgs=@('/nologo','/std:c++latest','/EHsc','/MD','/DWIN32','/DNOMINMAX','/DWIN32_LEAN_AND_MEAN','/DSPDLOG_COMPILED_LIB','/DSPDLOG_FMT_EXTERNAL','/DREX_HAS_D3D12=1','/clang:-msse4.1')+$defines+@(('/I'+$sdk+'/include'),('/I'+$root),'/Isrc','/Igenerated/default','/Zs','src/main.cpp','src/frame_stats.cpp','src/provider_free_disabled.cpp')
 Invoke-Bo3Owned $compiler $syntaxArgs $root actual-host-syntax $Evidence 40 $null|Out-Null
 Invoke-Bo3Owned $nativeExe @((Join-Path $Evidence native-fixture)) $root native-test $Evidence 20 $null|Out-Null
 $r.native=((Read-Bo3Text (Join-Path $Evidence native-test.stdout.txt))|ConvertFrom-Json)
 if(-not$r.native.pass-or$r.native.networkExports-ne40-or$r.native.networkRegistryEntries-lt40-or$r.native.hostDrivers-ne0){throw 'Actual native consumer/fence/factory fixture failed'}
 $r.nativeCompilerSha256=Get-ReadbackSha $compiler
 $r.rehearsal=Get-Content (Join-Path $Evidence rehearsal/result.json) -Raw|ConvertFrom-Json
 $r.pass=$true
}catch{$r.failure=$_.Exception.ToString();throw}finally{
 if('CannonballLive'-as[type]){try{if([CannonballLive]::JobPids().Length){Write-Bo3Json (Join-Path $Evidence cleanup-identities.json) @(Get-Bo3JobIdentities);[CannonballLive]::KillOwned()};$until=[DateTime]::UtcNow.AddSeconds(5);while(([CannonballLive]::JobPids().Length-or-not[CannonballLive]::LaunchedProcessesExited())-and[DateTime]::UtcNow-lt$until){[Threading.Thread]::Sleep(20)};[CannonballLive]::ReleaseJob()}catch{$r.cleanupFailure=$_.Exception.Message;$r.pass=$false}}
 if('CannonballLive'-as[type]){$r.jobEmpty=[CannonballLive]::JobPids().Length-eq0;$r.retainedProcessHandles=[CannonballLive]::RetainedProcessHandles()}
 $r.finishedUtc=[DateTime]::UtcNow.ToString('o')
 if('OutRunSnapshot'-as[type]){Write-Bo3Json (Join-Path $Evidence result.json) $r}
}
@{pass=$r.pass;failure=$r.failure;native=$r.native;rehearsalChecks=$r.rehearsal.checks;jobPolicyCases=$r.jobPolicyCases;helperOnlyStopPreservesRoot=$r.helperOnlyStopPreservesRoot;evidence=$Evidence}|ConvertTo-Json -Depth 4
