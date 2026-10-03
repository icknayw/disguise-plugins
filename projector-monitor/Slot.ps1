$brands=@('panasonic','epson')
function New-Slot($id,$config) {
    if (-not $config.brand) {$config.brand='panasonic'}
    return @{id=$id;config=$config;status=@{connection='offline';error='';checkedAt=$null};worker=$null;controlWorker=$null;control=$null;requests=@{};nextCheck=[DateTime]::UtcNow;generation=0;credentialError=$false}
}
function Stop-Slot($slot) {foreach($field in @('worker','controlWorker')){if($slot[$field]){$slot[$field].shell.Stop();$slot[$field].shell.Dispose();$slot[$field]=$null}}}
function Protect-Password([string]$password) {
    $bytes=[Text.Encoding]::UTF8.GetBytes($password)
    try { return [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)) }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
}
function Get-Password($config) {
    if (-not $config.passwordProtected) {return ''}
    $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($config.passwordProtected),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {return [Text.Encoding]::UTF8.GetString($bytes)} finally {[Array]::Clear($bytes,0,$bytes.Length)}
}
function Public-Config($slot) {
    $c=$slot.config
    return @{brand=$c.brand;name=$c.name;ip=$c.ip;port=$c.port;username=$c.username;hasPassword=[bool]$c.passwordProtected;credentialError=$slot.credentialError}
}
# $previous supplies the saved password when the form leaves it blank. A blank IP keeps the projector unconfigured.
function Validate-Config($value,$previous) {
    if ($value.ip -isnot [string] -or $value.name -isnot [string] -or $value.username -isnot [string]) {throw 'Enter a name, IP and username.'}
    $brand=if ($value.brand) {[string]$value.brand} else {'panasonic'}
    if ($brand -notin $brands) {throw 'Choose a supported projector brand.'}
    $ip=$value.ip.Trim()
    if ($ip) {
        if ($ip -notmatch '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$') {throw 'Enter a valid IPv4 address.'}
        $parts=@($ip.Split('.') | ForEach-Object {[int]$_})
        if (@($parts | Where-Object {$_ -gt 255}).Count -or $parts[0] -eq 0 -or $parts[0] -ge 224) {throw 'Enter a valid unicast IPv4 address.'}
    }
    $port=0
    if (-not [int]::TryParse([string]$value.port,[ref]$port) -or $port -lt 1 -or $port -gt 65535) {throw 'Port must be 1-65535.'}
    if ($value.name.Trim().Length -lt 1 -or $value.name.Length -gt 60) {throw 'Name must be 1-60 characters.'}
    if ($value.username.Trim().Length -lt 1 -or $value.username.Length -gt 64 -or $value.username -match '[\r\n:]') {throw 'Enter a valid username.'}
    $secret=if ($previous) {$previous.passwordProtected} else {''}
    if ($null -ne $value.password -and $value.password -ne '') {
        if($value.password -isnot [string] -or $value.password.Length -gt 128 -or $value.password -match '[\r\n]'){throw 'Invalid password.'}
        $secret=Protect-Password $value.password
    }
    return @{brand=$brand;name=$value.name.Trim();ip=$ip;port=$port;username=$value.username.Trim();passwordProtected=$secret}
}
# Runs Projector.ps1 on its own runspace so slow projectors never block the HTTP loop.
function Start-Worker($slot,$password,$action='') {
    $c=$slot.config;$shell=[PowerShell]::Create()
    [void]$shell.AddCommand((Join-Path $PSScriptRoot 'Projector.ps1')).AddParameter('Brand',$c.brand).AddParameter('Address',$c.ip).AddParameter('Port',$c.port).AddParameter('Username',$c.username).AddParameter('Password',$password).AddParameter('Action',$action)
    return @{shell=$shell;handle=$shell.BeginInvoke();generation=$slot.generation}
}
function Last-Output($worker) {$output=$worker.shell.EndInvoke($worker.handle);if($output.Count -gt 0){return $output[$output.Count-1]};return $null}
function Update-Projector($slot) {
    if (-not $slot.config.ip) {$slot.status=@{connection='offline';checkedAt=$null;error='Set the projector IP in Settings.'};return}
    if ($slot.controlWorker -and $slot.controlWorker.handle.IsCompleted) {
        try {
            $reply=Last-Output $slot.controlWorker
            $slot.control.state=if($reply -and $reply.ok){'succeeded'}else{'failed'}
            $slot.control.message=if($reply -and $reply.ok){'Command accepted'}elseif($reply){$reply.error}else{'No acknowledgement. Check status before retrying.'}
        } catch {$slot.control.state='failed';$slot.control.message='No acknowledgement. Check status before retrying.'}
        finally {$slot.controlWorker.shell.Dispose();$slot.controlWorker=$null;$slot.nextCheck=[DateTime]::UtcNow}
    }
    if ($slot.worker -and $slot.worker.handle.IsCompleted) {
        try {
            $reply=Last-Output $slot.worker
            # A status read that overlapped a command may be out of date; discard it.
            if ($slot.worker.generation -eq $slot.generation) {
                $slot.status=if($reply){$reply}else{@{connection='error';checkedAt=[DateTime]::UtcNow.ToString('o');error='Status reader failed.'}}
            }
        } catch {$slot.status=@{connection='error';checkedAt=[DateTime]::UtcNow.ToString('o');error='Status reader failed.'}}
        finally {$slot.worker.shell.Dispose();$slot.worker=$null}
    }
    if (-not $slot.worker -and -not $slot.controlWorker -and [DateTime]::UtcNow -ge $slot.nextCheck) {
        $slot.nextCheck=[DateTime]::UtcNow.AddSeconds(10)
        try {$password=Get-Password $slot.config; $slot.credentialError=$false}
        catch {
            $slot.credentialError=$true
            $slot.status=@{connection='auth';checkedAt=[DateTime]::UtcNow.ToString('o');error='Re-enter the password on this computer.'}
            return
        }
        $slot.worker=Start-Worker $slot $password
        $password=$null
    }
}
