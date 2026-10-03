# Epson ESC/VP21 over the projector's HTTP control API (default port 80, Digest user EPSONWEB).
# Dot-sourced by Projector.ps1.

function Invoke-Escvp([string]$command) {
    # Explicit allowlist. The web UI cannot send arbitrary commands.
    if ($command -notin @('PWR?','ERR?','LAMP?','SHUTTER?','SOURCE?','FREEZE?','SIGNAL?','SNO?','PWR ON','PWR OFF','SHUTTER ON','SHUTTER OFF')) { throw 'Command not allowed.' }
    $uri=[Uri]("http://${Address}:$Port/api/v01/control/escvp21?cmd="+$command.Replace(' ','+'))
    $request=[Net.HttpWebRequest]::Create($uri)
    $request.Timeout=3000; $request.ReadWriteTimeout=3000; $request.AllowAutoRedirect=$false
    if ($Password) {
        # Digest only, so the password is never sent in clear text over HTTP.
        $credentials=New-Object Net.CredentialCache
        $credentials.Add($uri,'Digest',(New-Object Net.NetworkCredential($Username,$Password)))
        $request.Credentials=$credentials
    }
    try { $response=$request.GetResponse() }
    catch {
        $e=$_.Exception; while ($e -and $e -isnot [Net.WebException]) { $e=$e.InnerException }
        if ($e -and $e.Response -and [int]$e.Response.StatusCode -eq 401) {
            $e.Response.Close()
            if ($Password) { throw 'Login rejected. Check username and password.' } else { throw 'Password required.' }
        }
        throw
    }
    try {
        $reader=New-Object IO.StreamReader($response.GetResponseStream(),[Text.Encoding]::ASCII)
        $buffer=New-Object char[] 4096; $length=0
        while ($length -lt $buffer.Length) { $read=$reader.Read($buffer,$length,$buffer.Length-$length); if ($read -le 0) { break }; $length+=$read }
        $body=[string]::new($buffer,0,$length)
    } finally { $response.Close() }
    # Replies look like "PWR=01" followed by the ":" prompt. ERR means not supported in the current state.
    $key=$command.Split(' ?')[0]
    if ($body -match "\b$key=([^\r\n:`"<]*)") { return $Matches[1].Trim() }
    if ($body -match '\bERR\b') { return $null }
    return ''
}

function Find-Label($map,$value) {
    if ($null -eq $value -or $value -eq '') { return $null }
    if ($map.ContainsKey($value)) { return $map[$value] }
    return $value
}

function Send-Control([string]$action) {
    $command=@{'power-on'='PWR ON';'power-off'='PWR OFF';'shutter-open'='SHUTTER OFF';'shutter-close'='SHUTTER ON'}[$action]
    if ($null -eq (Invoke-Escvp $command)) { throw 'Projector rejected the command.' }
}

function Read-Status($result) {
    $power=Invoke-Escvp 'PWR?'
    if ($power -notin @('00','01','02','03','04','05','09')) { throw 'Unexpected power response.' }
    $result.connection='online'
    $result.power=@{'00'='Standby';'01'='On';'02'='Warming up';'03'='Cooling';'04'='Standby';'05'='Abnormal standby';'09'='A/V standby'}[$power]
    $fault=Invoke-Escvp 'ERR?'
    $result.fault=Find-Label @{'00'='None';'01'='Fan';'03'='Light source';'04'='High temperature';'06'='Air filter';'07'='Air flow';'0A'='Light source hours exceeded';'0D'='Internal'} $fault
    if ($fault -and $fault -ne '00') { $result.error='Projector fault: '+$result.fault+'.' }
    $hours=Invoke-Escvp 'LAMP?'
    if ($hours -match '^\d+$') { $result.lightHours=[long]$hours }
    # Picture and serial queries answer ERR outside the On state. That is expected, not a fault.
    if ($power -ne '01') { return }
    $result.shutter=Find-Label @{'ON'='Closed';'01'='Closed';'OFF'='Open';'00'='Open'} (Invoke-Escvp 'SHUTTER?')
    $result.input=Find-Label @{'10'='Computer 1';'1F'='Computer 2';'20'='Component';'21'='BNC';'30'='HDMI 1';'A0'='DVI-D';'40'='Video';'41'='S-Video';'52'='LAN';'53'='WirelessHD';'56'='SDI 1';'57'='SDI 2';'60'='SDI';'70'='Content Playback';'80'='HDBaseT'} (Invoke-Escvp 'SOURCE?')
    $result.freeze=Find-Label @{'ON'='On';'01'='On';'OFF'='Off';'00'='Off'} (Invoke-Escvp 'FREEZE?')
    $result.signal=Find-Label @{'00'='No signal';'01'='Detected';'FF'='Unsupported'} (Invoke-Escvp 'SIGNAL?')
    $result.serial=Find-Label @{} (Invoke-Escvp 'SNO?')
}
