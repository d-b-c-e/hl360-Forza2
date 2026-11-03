function Set-Fm2BuildEnvironment([string]$Evidence,[scriptblock]$Tick){
 $vswhere='C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
 $vs=(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
 if($LASTEXITCODE-or-not$vs){throw 'MSVC environment unavailable'}
 $batch=Join-Path $Evidence msvc-environment.cmd
 [IO.File]::WriteAllText($batch,('@echo off'+"`r`n"+'call "'+$vs+'\VC\Auxiliary\Build\vcvars64.bat" >nul'+"`r`n"+'if errorlevel 1 exit /b 1'+"`r`n"+'set INCLUDE'+"`r`n"+'set LIB'+"`r`n"+'set LIBPATH'+"`r`n"+'set PATH'+"`r`n"))
 Invoke-Bo3Owned $env:ComSpec @('/d','/c',$batch) $Evidence msvc-environment $Evidence 20 $Tick | Out-Null
 $environmentText=Read-Bo3Text (Join-Path $Evidence msvc-environment.stdout.txt) 131072
 if(-not$environmentText){throw 'Incomplete MSVC environment output'}
 foreach($line in $environmentText.Split("`n")){if($line.TrimEnd("`r")-match'^(INCLUDE|LIB|LIBPATH|PATH)=(.*)$'){[Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process')}}
 if(-not$env:INCLUDE-or-not$env:LIB){throw 'Incomplete MSVC environment'}
}
