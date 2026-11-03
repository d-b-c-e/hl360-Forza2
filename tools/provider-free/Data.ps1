# Pure definitions. Explicit roots only; caller owns the CPU lease/budget.
function Copy-Fm2Tree([string]$Source,[string]$Destination,[scriptblock]$Tick){
 Assert-ReadbackPlain $Source;Assert-ReadbackPlain $Destination
 if(Test-Path -LiteralPath $Destination){throw 'Fresh private clone required'}
 if(Test-ReadbackWithin $Destination $Source){throw 'Clone cannot be under owner source'}
 [void][IO.Directory]::CreateDirectory($Destination)
 $rows=@()
 foreach($f in @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force|Sort-Object FullName)){
  &$Tick;Assert-ReadbackPlain $f.FullName
  $relative=[IO.Path]::GetRelativePath($Source,$f.FullName);$to=Join-Path $Destination $relative
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
  $sha=Get-ReadbackSha $f.FullName
  [IO.File]::Copy($f.FullName,$to,$false)
  if((Get-ReadbackSha $to)-cne$sha){throw 'Private clone bytes differ'}
  $rows+=@{relative=$relative;source=$f.FullName;path=$to;bytes=$f.Length;sha256=$sha}
 }
 foreach($d in @(Get-ChildItem -LiteralPath $Source -Recurse -Directory -Force)){Assert-ReadbackPlain $d.FullName;[void][IO.Directory]::CreateDirectory((Join-Path $Destination ([IO.Path]::GetRelativePath($Source,$d.FullName))))}
 return $rows
}
function Test-Fm2Disc($Rows,[string]$Manifest){
 $groups=@{}
 foreach($line in [IO.File]::ReadAllLines($Manifest)){
  if(-not$line-or$line.StartsWith('#')){continue}
  if($line-notmatch'^([a-f0-9]{64}) ([0-9]+) (.+)$'){throw 'Ambiguous disc verification row'}
  $relative=$Matches[3].Replace('/','\');if([IO.Path]::IsPathRooted($relative)-or$relative.Split('\')-contains'..'){throw 'Unsafe disc manifest relative path'}
  if(-not$groups.ContainsKey($relative)){$groups[$relative]=@()}
  $groups[$relative]+=@{sha256=$Matches[1].ToUpperInvariant();bytes=[long]$Matches[2]}
 }
 $actual=@{};foreach($r in $Rows){$actual[$r.relative]=$r}
 foreach($relative in $groups.Keys){if(-not$actual.ContainsKey($relative)){throw ('Missing disc member: '+$relative)};$r=$actual[$relative];if(-not@($groups[$relative]|Where-Object{$_.sha256-ceq$r.sha256-and$_.bytes-eq$r.bytes}).Count){throw ('Disc member differs: '+$relative)}}
 if($groups.Count-ne2344){throw 'Expected genuine 2344-file FM2 import contract'}
 return @{pass=$true;verified=$groups.Count;actual=$Rows.Count;additional=$Rows.Count-$groups.Count;manifest=$Manifest;manifestSha256=(Get-ReadbackSha $Manifest)}
}
