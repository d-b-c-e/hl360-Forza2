# Adapted from napo DiRT3 aa45b7c; preserve full raw cloud-pin attributes (0x80020).
# Pure guards and file transactions. Dot-sourcing does not load native code or touch owner state.
function Get-ReadbackSha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-ReadbackSparseKey([string]$Path){(@([Bo3OwnerIo]::Ranges($Path)|ForEach-Object{[string]$_.offset+':'+[string]$_.length})-join';')}
function Get-ReadbackExpectedSparseKey($File){(@($File.sparseRanges|Where-Object{$null-ne$_}|ForEach-Object{[string]$_.offset+':'+[string]$_.length})-join';')}
function Convert-ReadbackUtc($Value) {
    if($Value-is[DateTime]){if($Value.Kind-eq[DateTimeKind]::Unspecified){throw 'Timestamp must retain UTC or offset kind'};return $Value.ToUniversalTime()}
    if($Value-is[DateTimeOffset]){return $Value.UtcDateTime}
    if($Value-is[string]){if($Value-notmatch'(Z|[+-]\d\d:\d\d)$'){throw 'Timestamp must retain UTC or offset kind'};return [DateTimeOffset]::Parse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime}
    throw 'Invalid snapshot timestamp type'
}
function Get-ReadbackTicks($File,[string]$Field) {
    $numeric=$File.($Field+'Ticks')
    if($null-ne$numeric){return [long]::Parse([string]$numeric,[Globalization.CultureInfo]::InvariantCulture)}
    (Convert-ReadbackUtc $File.$Field).Ticks
}
function Test-ReadbackWithin([string]$Path,[string]$Root) {
    $p=[IO.Path]::GetFullPath($Path);$r=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Assert-ReadbackPlain([string]$Path) {
    for($p=[IO.Path]::GetFullPath($Path);$p;$p=[IO.Path]::GetDirectoryName($p)) {
        if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked path refused: $p"}
    }
}
function Save-ReadbackSnapshot([object[]]$Roots,[string]$Evidence) {
    $e=[IO.Path]::GetFullPath($Evidence);if(Test-Path -LiteralPath $e){throw 'Fresh snapshot directory required'}
    $seen=@()
    foreach($r in $Roots){
        if($r.kind -notin @('file','directory')){throw 'Unknown snapshot root kind'}
        if([IO.Path]::GetFullPath($r.path).TrimEnd('\')-eq[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($r.path)).TrimEnd('\')){throw 'Volume root snapshot refused'}
        foreach($prior in $seen){if((Test-ReadbackWithin $r.path $prior) -or (Test-ReadbackWithin $prior $r.path)){throw 'Overlapping snapshot roots'}}
        $seen+=[IO.Path]::GetFullPath($r.path)
        if(Test-Path -LiteralPath $r.path){$item=Get-Item -LiteralPath $r.path -Force;if($item.PSIsContainer -ne ($r.kind -eq 'directory')){throw 'Snapshot root type differs'}}
    }
    foreach($r in $Roots){if((Test-ReadbackWithin $e $r.path) -or (Test-ReadbackWithin $r.path $e)){throw 'Evidence and owner root overlap'};Assert-ReadbackPlain $r.path}
    [void][IO.Directory]::CreateDirectory($e);$entries=@();$i=0
    foreach($r in $Roots){
        $path=[IO.Path]::GetFullPath($r.path);$exists=Test-Path -LiteralPath $path;$files=@();$directories=@();$directoryMetadata=@()
        if($exists){
            if($r.kind -eq 'file'){$list=@(Get-Item -LiteralPath $path -Force)}else{$list=@(Get-ChildItem -LiteralPath $path -File -Recurse -Force);$directories=@(Get-ChildItem -LiteralPath $path -Directory -Recurse -Force|ForEach-Object {Assert-ReadbackPlain $_.FullName;$_.FullName})}
            if($r.kind-eq'directory'){foreach($d in @($path)+$directories){$item=Get-Item -LiteralPath $d -Force;$directoryMetadata+=@{path=$d;attributes=[int]$item.Attributes;creationUtc=$item.CreationTimeUtc.ToString('o');creationUtcTicks=$item.CreationTimeUtc.Ticks.ToString();lastWriteUtc=$item.LastWriteTimeUtc.ToString('o');lastWriteUtcTicks=$item.LastWriteTimeUtc.Ticks.ToString()}}}
            foreach($f in $list){Assert-ReadbackPlain $f.FullName;$relative=if($r.kind -eq 'file'){'payload'}else{$f.FullName.Substring($path.Length).TrimStart('\')};$backup=Join-Path (Join-Path $e $i) $relative;[void][IO.Directory]::CreateDirectory((Split-Path $backup));if([int]$f.Attributes-band512){[Bo3OwnerIo]::CopySparse($f.FullName,$backup,$false)}else{[IO.File]::Copy($f.FullName,$backup,$false)};$sha=Get-ReadbackSha $f.FullName;if((Get-ReadbackSha $backup) -cne $sha){throw 'Snapshot copy hash differs'};$files+=@{path=$f.FullName;backup=$backup;sha256=$sha;attributes=[int]$f.Attributes;lastWriteUtc=$f.LastWriteTimeUtc.ToString('o');lastWriteUtcTicks=$f.LastWriteTimeUtc.Ticks.ToString();creationUtc=$f.CreationTimeUtc.ToString('o');creationUtcTicks=$f.CreationTimeUtc.Ticks.ToString();sparseRanges=$(if([int]$f.Attributes-band512){@([Bo3OwnerIo]::Ranges($f.FullName))}else{@()})}}
        }
        $entries+=@{path=$path;kind=$r.kind;existed=$exists;directories=$directories;directoryMetadata=$directoryMetadata;files=$files};$i++
    }
    $manifest=@{schema='bo3-owner-snapshot@2';roots=$entries};$manifest|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $e manifest.json)
    return $manifest
}
function Restore-ReadbackSnapshot($Snapshot,[string]$AfterEvidence) {
    Assert-ReadbackPlain $AfterEvidence
    foreach($r in $Snapshot.roots){if((Test-ReadbackWithin $AfterEvidence $r.path) -or (Test-ReadbackWithin $r.path $AfterEvidence)){throw 'Restore evidence and owner root overlap'}}
    # Validate every backup before any restoration or removal, including roots restored later.
    foreach($r in $Snapshot.roots){foreach($f in $r.files){
        [void](Get-ReadbackTicks $f lastWriteUtc);if($f.creationUtc){[void](Get-ReadbackTicks $f creationUtc)}
        if(-not(Test-ReadbackWithin $f.path $r.path)){throw 'Snapshot file escaped root'}
        Assert-ReadbackPlain $f.backup
        if((Get-ReadbackSha $f.backup) -cne $f.sha256){throw 'Original backup changed; retain custody'}
    };foreach($d in $r.directoryMetadata){[void](Get-ReadbackTicks $d lastWriteUtc)}}
    [void][IO.Directory]::CreateDirectory($AfterEvidence)
    foreach($r in $Snapshot.roots){
        Assert-ReadbackPlain $r.path;$known=@{};foreach($f in $r.files){$known[$f.path]=$true}
        $current=if(-not(Test-Path -LiteralPath $r.path)){@()}elseif($r.kind -eq 'file'){@(Get-Item -LiteralPath $r.path -Force)}else{@(Get-ChildItem -LiteralPath $r.path -File -Recurse -Force)}
        foreach($f in $current){if(-not(Test-ReadbackWithin $f.FullName $r.path)){throw 'Restore path escaped root'};Assert-ReadbackPlain $f.FullName;if(-not $known.ContainsKey($f.FullName)){$archive=Join-Path $AfterEvidence ([Guid]::NewGuid().ToString('N')+'-'+$f.Name);[IO.File]::Copy($f.FullName,$archive,$false);if((Get-ReadbackSha $archive)-cne(Get-ReadbackSha $f.FullName)){throw 'Unexpected file archive hash differs; retain custody'};[IO.File]::SetAttributes($f.FullName,[IO.FileAttributes]::Normal);[IO.File]::Delete($f.FullName)}}
        foreach($f in $r.files){
            Assert-ReadbackPlain $f.path
            [void][IO.Directory]::CreateDirectory((Split-Path $f.path))
            if(Test-Path -LiteralPath $f.path){
                if((Get-ReadbackSha $f.path) -cne $f.sha256){
                    $archive=Join-Path $AfterEvidence ([Guid]::NewGuid().ToString('N')+'-'+[IO.Path]::GetFileName($f.path))
                    [IO.File]::Copy($f.path,$archive,$false)
                    if((Get-ReadbackSha $archive)-cne(Get-ReadbackSha $f.path)){throw 'Changed file archive hash differs; retain custody'}
                    $attributes=[int][IO.File]::GetAttributes($f.path)
                    if($attributes -band 1){[IO.File]::SetAttributes($f.path,[Enum]::ToObject([IO.FileAttributes],($attributes -band (-bnot 1))))}
                    # Overwrite existing bytes without replacing cloud-pin flags, ACL or file identity.
                    if([int]$f.attributes-band512){[Bo3OwnerIo]::CopySparse($f.backup,$f.path,$true)}else{$sourceStream=[IO.File]::OpenRead($f.backup);$targetStream=[IO.FileStream]::new($f.path,[IO.FileMode]::Open,[IO.FileAccess]::Write,([IO.FileShare]::ReadWrite-bor[IO.FileShare]::Delete));try{$sourceStream.CopyTo($targetStream);$targetStream.SetLength($sourceStream.Length)}finally{$sourceStream.Dispose();$targetStream.Dispose()}}
                }
            }else{if([int]$f.attributes-band512){[Bo3OwnerIo]::CopySparse($f.backup,$f.path,$false)}else{[IO.File]::Copy($f.backup,$f.path,$false)}}
            if(([int]$f.attributes-band512)-and((Get-ReadbackSparseKey $f.path)-cne(Get-ReadbackExpectedSparseKey $f))){[Bo3OwnerIo]::CopySparse($f.backup,$f.path,$true)}
            if(-not([int]$f.attributes-band512)-and([int][IO.File]::GetAttributes($f.path)-band512)){[Bo3OwnerIo]::SetSparse($f.path,$false)}
            $write=Get-ReadbackTicks $f lastWriteUtc
            if([IO.File]::GetLastWriteTimeUtc($f.path).Ticks-ne$write){[IO.File]::SetLastWriteTimeUtc($f.path,[DateTime]::new($write,[DateTimeKind]::Utc))}
            if($f.creationUtc){$created=Get-ReadbackTicks $f creationUtc;if([IO.File]::GetCreationTimeUtc($f.path).Ticks-ne$created){[IO.File]::SetCreationTimeUtc($f.path,[DateTime]::new($created,[DateTimeKind]::Utc))}}
            # Windows exposes legitimate cloud flags not listed in the .NET FileAttributes enum.
            if([int][IO.File]::GetAttributes($f.path) -ne $f.attributes){[IO.File]::SetAttributes($f.path,[Enum]::ToObject([IO.FileAttributes],[int]$f.attributes))}
        }
        if($r.kind -eq 'directory'){
            if($r.existed){[void][IO.Directory]::CreateDirectory($r.path);foreach($d in $r.directories){[void][IO.Directory]::CreateDirectory($d)}}
            if(Test-Path -LiteralPath $r.path){$dirs=@(Get-ChildItem -LiteralPath $r.path -Directory -Recurse -Force|Sort-Object {$_.FullName.Length} -Descending);foreach($d in $dirs){Assert-ReadbackPlain $d.FullName;if($d.FullName -notin $r.directories -and @(Get-ChildItem -LiteralPath $d.FullName -Force).Count -eq 0){[IO.Directory]::Delete($d.FullName,$false)}};if(-not $r.existed -and @(Get-ChildItem -LiteralPath $r.path -Force).Count -eq 0){[IO.Directory]::Delete($r.path,$false)}}
        }
        # Directory timestamps must be last, after creating/removing entries.
        foreach($d in @($r.directoryMetadata|Sort-Object {$_.path.Length} -Descending)){Assert-ReadbackPlain $d.path;if($d.creationUtc){[IO.Directory]::SetCreationTimeUtc($d.path,[DateTime]::new((Get-ReadbackTicks $d creationUtc),[DateTimeKind]::Utc))};[IO.File]::SetAttributes($d.path,[Enum]::ToObject([IO.FileAttributes],[int]$d.attributes));[IO.Directory]::SetLastWriteTimeUtc($d.path,[DateTime]::new((Get-ReadbackTicks $d lastWriteUtc),[DateTimeKind]::Utc))}
    }
}
function Test-ReadbackRestored($Snapshot) {
    $errors=@();$checked=0
    foreach($r in $Snapshot.roots){
        if((Test-Path -LiteralPath $r.path) -ne [bool]$r.existed){$errors+='root presence: '+$r.path}
        $known=@($r.files|ForEach-Object path)
        foreach($f in $r.files){$checked++;if(-not(Test-Path -LiteralPath $f.path) -or (Get-ReadbackSha $f.path) -cne $f.sha256){$errors+='hash: '+$f.path}elseif([int][IO.File]::GetAttributes($f.path)-ne[int]$f.attributes){$errors+='attributes: '+$f.path}elseif([IO.File]::GetLastWriteTimeUtc($f.path).Ticks-ne(Get-ReadbackTicks $f lastWriteUtc)){$errors+='timestamp: '+$f.path}elseif($f.creationUtc-and[IO.File]::GetCreationTimeUtc($f.path).Ticks-ne(Get-ReadbackTicks $f creationUtc)){$errors+='creation timestamp: '+$f.path}}
        foreach($f in $r.files){if(([int]$f.attributes-band512)-and(Test-Path -LiteralPath $f.path)-and(Get-ReadbackSparseKey $f.path)-cne(Get-ReadbackExpectedSparseKey $f)){$errors+='sparse allocation: '+$f.path}}
        if($r.kind -eq 'directory' -and (Test-Path -LiteralPath $r.path)){
            foreach($f in Get-ChildItem -LiteralPath $r.path -File -Recurse -Force){if($f.FullName -notin $known){$errors+='new file: '+$f.FullName}}
            $dirs=@(Get-ChildItem -LiteralPath $r.path -Directory -Recurse -Force|ForEach-Object FullName)
            if((@($r.directories|Sort-Object) -join "`n") -cne (@($dirs|Sort-Object) -join "`n")){$errors+='directory set: '+$r.path}
            foreach($d in $r.directoryMetadata){if(($d.creationUtc-and[IO.Directory]::GetCreationTimeUtc($d.path).Ticks-ne(Get-ReadbackTicks $d creationUtc)) -or [int][IO.File]::GetAttributes($d.path)-ne[int]$d.attributes -or [IO.Directory]::GetLastWriteTimeUtc($d.path).Ticks-ne(Get-ReadbackTicks $d lastWriteUtc)){$errors+='directory metadata: '+$d.path}}
        }
    }
    return [pscustomobject]@{pass=($errors.Count -eq 0);files=$checked;errors=$errors;method='independent fresh SHA-256 enumeration'}
}
