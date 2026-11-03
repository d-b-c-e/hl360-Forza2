# Exact inert launch/setup/configure/dry-run seam shared by admission and CPU.
# All census observations are from this fresh own job, never adopted processes.
function Add-Fm2ToolchainCensus($Context,[string]$Evidence){
 $changed=$false
 foreach($identity in @(Get-Bo3JobIdentities)){
  $key=[string]$identity.pid+':'+[string]$identity.birth
  if(-not$Context.seen.ContainsKey($key)){$Context.seen[$key]=@{pid=$identity.pid;birth=$identity.birth;image=$identity.image;phase=$Context.phase};$changed=$true}
 }
 if($changed){Write-Bo3Json (Join-Path $Evidence toolchain-identities.json) @($Context.seen.Values)}
}
function Invoke-Fm2ToolchainSmoke([string]$Root,[string]$Evidence,[string]$Sdk){
 $context=@{seen=@{};phase='vcvars64-setup'}
 Set-Fm2BuildEnvironment $Evidence {Add-Fm2ToolchainCensus $context $Evidence}
 $tools=@{cmake='C:\Program Files\CMake\bin\cmake.exe';clang='C:\Program Files\LLVM\bin\clang.exe';clangxx='C:\Program Files\LLVM\bin\clang++.exe';ninja='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe';readobj='C:\Program Files\LLVM\bin\llvm-readobj.exe';lld='C:\Program Files\LLVM\bin\lld-link.exe'}
 foreach($name in @('cmake','ninja','clang','clangxx','readobj','lld')){
  $context.phase=$name+'-version';$identity=Invoke-Bo3Owned $tools[$name] @('--version') $Root ('tool-'+$name) $Evidence 15 {Add-Fm2ToolchainCensus $context $Evidence} $true 5
  $key=[string]$identity.pid+':'+[string]$identity.birth;$context.seen[$key]=@{pid=$identity.pid;birth=$identity.birth;image=$identity.image;phase=$context.phase}
 }
 $context.phase='candidate-cmake-configure';$build=Join-Path $Evidence candidate-cmake
 $identity=Invoke-Bo3Owned $tools.cmake (Get-Fm2ConfigureArguments $Root $build $Sdk $tools) $Root tool-configure $Evidence 90 {Add-Fm2ToolchainCensus $context $Evidence} $true 5
 $key=[string]$identity.pid+':'+[string]$identity.birth;$context.seen[$key]=@{pid=$identity.pid;birth=$identity.birth;image=$identity.image;phase=$context.phase}
 $context.phase='candidate-ninja-dry-run'
 $identity=Invoke-Bo3Owned $tools.ninja @('-C',$build,'-n','-v','forza2') $Root tool-dry-run $Evidence 20 {Add-Fm2ToolchainCensus $context $Evidence} $true 5
 $key=[string]$identity.pid+':'+[string]$identity.birth;$context.seen[$key]=@{pid=$identity.pid;birth=$identity.birth;image=$identity.image;phase=$context.phase}
 $dry=Read-Bo3Text (Join-Path $Evidence tool-dry-run.stdout.txt) 4194304
 if(-not$dry-or$dry-match'(?i)rexglue(\.exe)?[" ]+codegen|codegen_skipped|Generating recompiled|translate_'){throw 'Real candidate dry-run contains a generator invocation'}
 $model=Read-Bo3Text (Join-Path $build build.ninja) 4194304
 if(-not$model-or$model-match'COMMAND = .*\bcodegen\b'){throw 'Generated candidate tree still contains a codegen command'}
 if(Test-Path -LiteralPath (Join-Path $build forza2.exe)){throw 'Inert smoke unexpectedly built the game target'}
 $until=[DateTime]::UtcNow.AddSeconds(10);while([CannonballLive]::JobPids().Length-and[DateTime]::UtcNow-lt$until){Add-Fm2ToolchainCensus $context $Evidence;[Threading.Thread]::Sleep(5)}
 if([CannonballLive]::JobPids().Length){throw 'Inert real toolchain job not quiescent'}
 Write-Bo3Json (Join-Path $Evidence toolchain-identities.json) @($context.seen.Values)
 $pins=@(foreach($group in ($context.seen.Values|Group-Object image)){$first=$group.Group[0];@{path=$first.image;sha256=(Get-ReadbackSha $first.image);roles=@($group.Group.phase|Sort-Object -Unique);identities=@($group.Group)}})
 $result=@{pass=$true;sourceRoot=$Root;build=$build;noGameBuild=$true;noGame=$true;noRenderer=$true;noHooks=$true;noDevice=$true;noOwnerWrite=$true;noLease=$true;dryRunNoGenerator=$true;setupTelemetryDisabled=$true;dryRunSha256=(Get-ReadbackSha (Join-Path $Evidence tool-dry-run.stdout.txt));pins=$pins;tools=$tools;jobEmpty=$true;roleNotes=@{'vcvars64-setup'='Actual VS discovery/cmd/registry setup; source-supported telemetry opt-out';'candidate-cmake-configure'='Exact scratch candidate CMake configure and tiny compiler ABI/Threads probes; no game target built';'candidate-ninja-dry-run'='Actual candidate Ninja graph expansion, zero generator commands';'version'='Inert --version of actual CPU entrypoint'}}
 Write-Bo3Json (Join-Path $Evidence toolchain-result.json) $result
 [CannonballLive]::ReleaseJob();return $result
}
