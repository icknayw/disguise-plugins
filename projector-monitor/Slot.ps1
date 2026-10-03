function Protect-Password([string]$password) {
    $bytes=[Text.Encoding]::UTF8.GetBytes($password)
    try { return [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)) }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
}
function Get-Password {
    if (-not $script:config.passwordProtected) {return ''}
    $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($script:config.passwordProtected),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {return [Text.Encoding]::UTF8.GetString($bytes)} finally {[Array]::Clear($bytes,0,$bytes.Length)}
}
function Public-Config {
    return @{name=$script:config.name;ip=$script:config.ip;port=$script:config.port;username=$script:config.username;hasPassword=[bool]$script:config.passwordProtected;credentialError=$script:credentialError}
}
function Validate-Config($value) {
    if ($value.ip -isnot [string] -or $value.name -isnot [string] -or $value.username -isnot [string]) {throw 'Enter a name, IP and username.'}
    $ip=$value.ip.Trim()
    if ($ip -notmatch '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$') {throw 'Enter a valid IPv4 address.'}
    $parts=@($ip.Split('.') | ForEach-Object {[int]$_})
    if (@($parts | Where-Object {$_ -gt 255}).Count -or $parts[0] -eq 0 -or $parts[0] -ge 224) {throw 'Enter a valid unicast IPv4 address.'}
    $port=0
    if (-not [int]::TryParse([string]$value.port,[ref]$port) -or $port -lt 1 -or $port -gt 65535) {throw 'Port must be 1-65535.'}
    if ($value.name.Trim().Length -lt 1 -or $value.name.Length -gt 60) {throw 'Name must be 1-60 characters.'}
    if ($value.username.Trim().Length -lt 1 -or $value.username.Length -gt 64 -or $value.username -match '[\r\n:]') {throw 'Enter a valid username.'}
    $secret=$script:config.passwordProtected
    if ($null -ne $value.password -and $value.password -ne '') {
        if($value.password -isnot [string] -or $value.password.Length -gt 128 -or $value.password -match '[\r\n]'){throw 'Invalid password.'}
        $secret=Protect-Password $value.password
    }
    return @{name=$value.name.Trim();ip=$ip;port=$port;username=$value.username.Trim();passwordProtected=$secret}
}
function Update-Projector {
    if (-not $script:config.ip) {$script:status=@{connection='offline';checkedAt=$null;error='Set the projector IP in Settings.'};return}
    if ($script:controlWorker -and $script:controlWorker.handle.IsCompleted) {
        try {
            $output=$script:controlWorker.shell.EndInvoke($script:controlWorker.handle)
            $reply=if($output.Count -gt 0){$output[$output.Count-1]}else{$null}
            $script:control.state=if($reply -and $reply.ok){'succeeded'}else{'failed'}
            $script:control.message=if($reply -and $reply.ok){'Command accepted'}elseif($reply){$reply.error}else{'No acknowledgement. Check status before retrying.'}
        } catch {$script:control.state='failed';$script:control.message='No acknowledgement. Check status before retrying.'}
        finally {$script:controlWorker.shell.Dispose();$script:controlWorker=$null;$script:nextCheck=[DateTime]::UtcNow}
    }
    if ($script:worker -and $script:worker.handle.IsCompleted) {
        try {
            $output=$script:worker.shell.EndInvoke($script:worker.handle)
            if($script:worker.generation -eq $script:generation) {
                if($output.Count -gt 0) {$script:status=$output[$output.Count-1]}
                else {$script:status=@{connection='error';checkedAt=[DateTime]::UtcNow.ToString('o');error='Status reader failed.'}}
            }
        } catch {$script:status=@{connection='error';checkedAt=[DateTime]::UtcNow.ToString('o');error='Status reader failed.'}}
        finally {$script:worker.shell.Dispose();$script:worker=$null}
    }
    if (-not $script:worker -and -not $script:controlWorker -and [DateTime]::UtcNow -ge $script:nextCheck) {
        $script:nextCheck=[DateTime]::UtcNow.AddSeconds(10)
        try {$password=Get-Password; $script:credentialError=$false}
        catch {
            $script:credentialError=$true
            $script:status=@{connection='auth';checkedAt=[DateTime]::UtcNow.ToString('o');error='Re-enter the password on this computer.'}
            return
        }
        $shell=[PowerShell]::Create()
        [void]$shell.AddCommand((Join-Path $PSScriptRoot 'Projector.ps1')).AddParameter('Address',$script:config.ip).AddParameter('Port',$script:config.port).AddParameter('Username',$script:config.username).AddParameter('Password',$password)
        $script:worker=@{shell=$shell;handle=$shell.BeginInvoke();generation=$script:generation}
        $password=$null
    }
}
