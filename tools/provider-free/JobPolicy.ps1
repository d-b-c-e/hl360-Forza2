# Only identities already returned by the fresh, private job are classified here.
function Get-OwnedJobRole($Identity,$RootIdentity,$Plan) {
 if($Identity.birth -lt $RootIdentity.birth){return 'unknown-epoch'}
 $image=[IO.Path]::GetFullPath($Identity.image)
 if($image -ieq [IO.Path]::GetFullPath($Plan.python)){
  if($Identity.pid -eq $RootIdentity.pid -and $Identity.birth -eq $RootIdentity.birth){return 'root'}
  return 'unknown-python'
 }
 if($image -ieq [IO.Path]::GetFullPath($Plan.candidate)){return 'game'}
 if($image -ieq [IO.Path]::GetFullPath($Plan.capture)){return 'capture'}
 if($image -ieq [IO.Path]::GetFullPath($Plan.consoleHost)){return 'console-host'}
 return 'unknown-image'
}
