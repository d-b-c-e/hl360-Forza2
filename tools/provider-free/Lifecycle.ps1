# Adapted from napo DiRT3 lifecycle; tested callback core, not a claim of live Cannonball qualification.
# Shared by the real executor and inert callback rehearsals. No native work on dot-source.
function Invoke-CannonballLifecycle([hashtable]$Actions,[string]$Journal) {
    $s=[ordered]@{phase='preflight';status='INCOMPLETE';lease=$false;observer=$false;snapshot=$false;install=$false;launch=$false;quiescent=$false;restored=$false;released=$false;failure=$null;cleanupErrors=@()}
    function Phase([string]$Name){$s.phase=$Name;[IO.File]::AppendAllText($Journal,([DateTime]::UtcNow.ToString('o')+' '+$Name+"`r`n"));& $Actions[$Name]}
    try{
        Phase Preflight
        Phase Lease;$s.lease=$true
        $s.observer=$true;Phase Observe
        Phase Snapshot;$s.snapshot=$true
        $s.install=$true;Phase Install
        Phase Arm
        $s.launch=$true;Phase Launch
        Phase Fence
        Phase Steps;$s.status='PASS'
    }catch{$s.failure=$_.Exception.Message;$s.status='BLOCKED'}
    finally{
        if($Actions.ContainsKey('LeaseHeld') -and (& $Actions.LeaseHeld)){$s.lease=$true}
        if($s.lease){
            try{Phase Close;$s.quiescent=$true}catch{$s.cleanupErrors+='close: '+$_.Exception.Message}
            if($s.quiescent){
                try{if($s.install){Phase Rollback;Phase Restore};if($s.snapshot){Phase Verify};$s.restored=$true}catch{$s.cleanupErrors+='restore: '+$_.Exception.Message}
            }
            if($s.observer){try{Phase StopObserver;$s.observer=$false}catch{$s.cleanupErrors+='observer: '+$_.Exception.Message}}
            if($s.quiescent -and $s.restored -and -not $s.observer){try{Phase Release;$s.released=$true}catch{$s.cleanupErrors+='release: '+$_.Exception.Message}}
            if(-not $s.released){$s.status='CUSTODY_RETAINED'}
        }
    }
    return [pscustomobject]$s
}
