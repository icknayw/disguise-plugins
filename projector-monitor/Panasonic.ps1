# Panasonic NTCONTROL over TCP (default port 1024). Dot-sourced by Projector.ps1.

function Read-Line($stream) {
    $bytes=New-Object 'Collections.Generic.List[byte]'
    while ($bytes.Count -lt 4096) {
        $value=$stream.ReadByte()
        if ($value -lt 0) { throw 'Projector closed the connection.' }
        if ($value -eq 13) { return [Text.Encoding]::ASCII.GetString($bytes.ToArray()) }
        $bytes.Add([byte]$value)
    }
    throw 'Projector response is too long.'
}

function Query-Projector([string]$command) {
    # Explicit allowlist. The web UI cannot send arbitrary commands.
    if ($command -notin @('QID','QSN','QPW','QSH','QIN','QFZ','QTM:0','QTM:1','QVX:RTMS1','QVX:LRTS3=00','QVX:POWI1','QVX:SVRS0','PON','POF','OSH:0','OSH:1')) { throw 'Command not allowed.' }
    $client=New-Object Net.Sockets.TcpClient
    try {
        $connect=$client.ConnectAsync($Address,$Port)
        if (-not $connect.Wait(1500)) { throw 'Projector connection timed out.' }
        $stream=$client.GetStream()
        $stream.ReadTimeout=1500; $stream.WriteTimeout=1500
        $hello=Read-Line $stream
        $prefix=''
        if ($hello -match '^NTCONTROL 1 ([0-9a-fA-F]{8})$') {
            if (-not $Password) { throw 'Password required.' }
            $challenge=$Matches[1]
            $hash=[Security.Cryptography.MD5]::Create()
            try {
                $prefix=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Username+':'+$Password+':'+$challenge)))).Replace('-','').ToLowerInvariant()
            } finally { $hash.Dispose() }
        } elseif ($hello -ne 'NTCONTROL 0') {
            throw 'Unsupported projector authentication mode.'
        }
        $payload=[Text.Encoding]::ASCII.GetBytes($prefix+'00'+$command+"`r")
        $stream.Write($payload,0,$payload.Length)
        $response=Read-Line $stream
        if ($response -eq 'ERRA' -or $response -eq '00ERRA') { throw 'Login rejected. Check username and password.' }
        if ($response.StartsWith('00')) { $response=$response.Substring(2) }
        if ($response -match '^ER') { return $null }
        return $response
    } finally { $client.Dispose() }
}

function Parse-Temperature($value) {
    if ($value -match '^([+-]?\d{4})/[+-]?\d{4}$') { return [int]$Matches[1] }
    return $null
}

function Send-Control([string]$action) {
    $command=@{'power-on'='PON';'power-off'='POF';'shutter-open'='OSH:0';'shutter-close'='OSH:1'}[$action]
    $reply=Query-Projector $command
    if ($null -eq $reply) { throw 'Projector rejected the command.' }
    if ($reply -ne $command) { throw 'Unexpected acknowledgement. Check status before retrying.' }
}

function Read-Status($result) {
    $power=Query-Projector 'QPW'
    if ($power -notin @('000','001')) { throw 'Unexpected power response.' }
    $result.connection='online'
    $result.power=@{'000'='Standby';'001'='On'}[$power]
    $queries=[ordered]@{model='QID';serial='QSN';shutter='QSH';input='QIN';freeze='QFZ';intakeC='QTM:0';exhaustC='QTM:1';projectorHours='QVX:RTMS1';lightHours='QVX:LRTS3=00';powerState='QVX:POWI1';firmware='QVX:SVRS0'}
    foreach ($field in $queries.Keys) {
        $value=Query-Projector $queries[$field]
        switch ($field) {
            shutter { $result.shutter=@{'0'='Open';'1'='Closed'}[[string]$value] }
            freeze { $result.freeze=@{'0'='Off';'1'='On'}[[string]$value] }
            input {
                $inputs=@{'HD1'='HDMI 1';'HD2'='HDMI 2';'DP1'='DisplayPort';'DM1,SD1'='Slot / SDI';'DM1,DL1'='Slot / DIGITAL LINK';'DM1,WP1'='Slot / PressIT';'DM1,TP1'='Slot';'DM1,OP1'='Slot / SDI OPT 1';'DM1,OP2'='Slot / SDI OPT 2'}
                $result.input=if ($inputs.ContainsKey([string]$value)) {$inputs[$value]} else {$value}
            }
            intakeC { $result.intakeC=Parse-Temperature $value }
            exhaustC { $result.exhaustC=Parse-Temperature $value }
            projectorHours { if ($value -match '^RTMS1=(\d+)$') {$result.projectorHours=[long]$Matches[1]} }
            lightHours { if ($value -match '^LRTS3=00:(\d+)$') {$result.lightHours=[long]$Matches[1]} }
            powerState { if ($value -match '^POWI1=\+0000([1-4])$') {$result.power=@{'1'='Standby';'2'='Warming up';'3'='On';'4'='Cooling'}[$Matches[1]]} }
            firmware { if ($value -match '^SVRS0=(.+)$') {$result.firmware=$Matches[1]} }
            default { $result[$field]=$value }
        }
        Start-Sleep -Milliseconds 80
    }
}
