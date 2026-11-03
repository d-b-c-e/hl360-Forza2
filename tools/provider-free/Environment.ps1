function Set-Fm2BuildEnvironment([string]$Evidence,[scriptblock]$Tick){
 $vswhere='C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
 Invoke-Bo3Owned $vswhere @('-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath') $Evidence vswhere-discovery $Evidence 20 $Tick $true 5|Out-Null
 $vs=(Read-Bo3Text (Join-Path $Evidence vswhere-discovery.stdout.txt)).Trim()
 if(-not$vs){throw 'MSVC environment unavailable'}
 $batch=Join-Path $Evidence msvc-environment.cmd
 [IO.File]::WriteAllText($batch,('@echo off'+"`r`n"+'set VSCMD_SKIP_SENDTELEMETRY=1'+"`r`n"+'call "'+$vs+'\VC\Auxiliary\Build\vcvars64.bat" >nul'+"`r`n"+'if errorlevel 1 exit /b 1'+"`r`n"+'set INCLUDE'+"`r`n"+'set LIB'+"`r`n"+'set LIBPATH'+"`r`n"+'set PATH'+"`r`n"))
 Invoke-Bo3Owned $env:ComSpec @('/d','/c',$batch) $Evidence msvc-environment $Evidence 20 $Tick $true 5 | Out-Null
 $environmentText=Read-Bo3Text (Join-Path $Evidence msvc-environment.stdout.txt) 131072
 if(-not$environmentText){throw 'Incomplete MSVC environment output'}
 foreach($line in $environmentText.Split("`n")){if($line.TrimEnd("`r")-match'^(INCLUDE|LIB|LIBPATH|PATH)=(.*)$'){[Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process')}}
 if(-not$env:INCLUDE-or-not$env:LIB){throw 'Incomplete MSVC environment'}
}
function Get-Fm2ConfigureArguments([string]$Source,[string]$Build,[string]$Sdk,$Tools){
 @('-S',$Source,'-B',$Build,'-G','Ninja',('-DCMAKE_MAKE_PROGRAM='+$Tools.ninja),('-DCMAKE_C_COMPILER='+$Tools.clang),('-DCMAKE_CXX_COMPILER='+$Tools.clangxx),('-DCMAKE_PREFIX_PATH='+$Sdk),'-DCMAKE_BUILD_TYPE=Release','-DFORZA2_BUILD_LAUNCHER=OFF','-DFORZA2_USE_COMMITTED_GENERATED=ON','-DCMAKE_EXPORT_COMPILE_COMMANDS=ON')
}
function Get-Fm2MsvcTools([string]$Evidence){
 $text=Read-Bo3Text (Join-Path $Evidence msvc-environment.stdout.txt) 131072
 if(-not$text){throw 'Complete MSVC environment evidence required'}
 [string]$pathLine=$text.Split("`n")|Where-Object{$_.StartsWith('PATH=',[StringComparison]::OrdinalIgnoreCase)}|Select-Object -First 1
 if(-not$pathLine){throw 'MSVC PATH evidence missing'}
 $folders=$pathLine.Substring(5).TrimEnd("`r").Split(';');$result=@{}
 foreach($toolName in @('link','rc','mt')){$found=@($folders|Where-Object{$_-and(Test-Path -LiteralPath (Join-Path $_ ($toolName+'.exe')))}|Select-Object -First 1);if(-not$found.Count){throw ('Build tool missing: '+$toolName)};$result[$toolName]=[IO.Path]::GetFullPath((Join-Path $found[0] ($toolName+'.exe')))}
 return $result
}
