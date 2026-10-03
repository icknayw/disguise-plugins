param([int]$HttpPort=18743)
# Windows PowerShell 5.1; ping monitoring runs outside Designer.
$ErrorActionPreference = 'Stop'
$viewPath=Join-Path $PSScriptRoot 'view.json'
$script:view=@{size='compact';columns=1}
if(Test-Path $viewPath){$v=Get-Content $viewPath -Raw|ConvertFrom-Json;if($v.size -notin @('compact','standard','large') -or $v.columns -notin @(1,2,4)){throw 'Invalid view settings'};$script:view=@{size=$v.size;columns=[int]$v.columns}}
function Dimensions($settings=$false){if($settings){return @(540,520)};$width=@{compact=230;standard=280;large=330}[$script:view.size];$cols=[Math]::Min([int]$script:view.columns,[Math]::Max(1,$script:devices.Count));$rows=[Math]::Max(1,[Math]::Ceiling($script:devices.Count/$cols));return @([int]($width*$cols+($cols-1)*4+12),[int]($rows*54+52))}
$configPath = Join-Path $PSScriptRoot 'devices.json'
$script:devices = @()
$script:results = @()
$script:jobs = @()
$script:generation = 0
$script:nextCheck = [DateTime]::UtcNow
$script:running = $true
$listener = New-Object System.Net.HttpListener

function Validate-Devices($items) {
    $clean = @()
    if ($null -eq $items) { return ,$clean }
    foreach ($item in $items) {
        if ($item.name -isnot [string] -or $item.ip -isnot [string]) { throw 'Name and IP must be text.' }
        $name = $item.name.Trim()
        $ip = $item.ip.Trim()
        if ($name.Length -gt 60) { throw 'Names must be 60 characters or fewer.' }
        if ($ip) {
            if ($ip -notmatch '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$') { throw 'Enter an IPv4 address such as 192.168.1.10.' }
            $parts = @($ip.Split('.') | ForEach-Object { [int]$_ })
            if (@($parts | Where-Object { $_ -gt 255 }).Count -or $parts[0] -eq 0 -or $parts[0] -ge 224 -or $ip -eq '255.255.255.255') { throw 'Enter a valid unicast IPv4 address.' }
            if (-not $name) { throw 'Give each configured device a name.' }
        }
        $clean += @{name=$name; ip=$ip}
    }
    return ,$clean
}

function Reset-Results {
    $script:generation++
    $script:results = @($script:devices | ForEach-Object {
        @{name=$_.name; ip=$_.ip; status=$(if ($_.ip) {'checking'} else {'empty'}); checkedAt=$null; latencyMs=$null; detail=''}
    })
    $script:nextCheck = [DateTime]::UtcNow
}

function Update-Pings {
    $remaining = @()
    foreach ($job in $script:jobs) {
        if (-not $job.task.IsCompleted) { $remaining += $job; continue }
        try {
            if ($job.generation -eq $script:generation) {
                $result = $script:results[$job.index]
                $result.checkedAt = [DateTime]::UtcNow.ToString('o')
                if ($job.task.IsFaulted -or $job.task.IsCanceled) {
                    $result.status = 'error'; $result.detail = 'Ping could not run.'; $result.latencyMs = $null
                } else {
                    $reply = $job.task.Result
                    if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                        $result.status = 'online'; $result.latencyMs = $reply.RoundtripTime; $result.detail = ''
                    } else {
                        $result.status = 'offline'; $result.latencyMs = $null; $result.detail = [string]$reply.Status
                    }
                }
            }
        } finally { $job.ping.Dispose() }
    }
    $script:jobs = $remaining
    if ($script:jobs.Count -eq 0 -and [DateTime]::UtcNow -ge $script:nextCheck) {
        $script:nextCheck = [DateTime]::UtcNow.AddSeconds(10)
        for ($i=0; $i -lt $script:devices.Count; $i++) {
            if (-not $script:devices[$i].ip) { continue }
            $ping = New-Object System.Net.NetworkInformation.Ping
            try {
                $task = $ping.SendPingAsync([string]$script:devices[$i].ip, 1500)
                $script:jobs += @{ping=$ping; task=$task; index=$i; generation=$script:generation}
            } catch {
                $ping.Dispose()
                $script:results[$i].status='error'
                $script:results[$i].detail='Ping could not start.'
                $script:results[$i].checkedAt=[DateTime]::UtcNow.ToString('o')
                $script:results[$i].latencyMs=$null
            }
        }
    }
}

function Send-Response($context, [int]$code, [string]$body, [string]$type='application/json; charset=utf-8') {
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $context.Response.StatusCode=$code
    $context.Response.ContentType=$type
    $context.Response.Headers['Cache-Control']='no-store'
    $context.Response.Headers['X-Content-Type-Options']='nosniff'
    $context.Response.Headers['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'"
    $context.Response.ContentLength64=$bytes.Length
    $context.Response.OutputStream.Write($bytes,0,$bytes.Length)
    $context.Response.Close()
}

try {
    if (Test-Path -LiteralPath $configPath) {
        $script:devices = Validate-Devices (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json)
    } else {
        $script:devices = @()
    }
    Reset-Results
    $listener.Prefixes.Add("http://localhost:$HttpPort/")
    $listener.Start()
    $pending = $listener.GetContextAsync()
    while ($script:running) {
        Update-Pings
        if (-not $pending.IsCompleted) { Start-Sleep -Milliseconds 30; continue }
        $context = $pending.GetAwaiter().GetResult()
        $pending = $listener.GetContextAsync()
        try {
            $request = $context.Request
            $path = $request.Url.AbsolutePath
            if (-not [Net.IPAddress]::IsLoopback($request.RemoteEndPoint.Address)) {
                Send-Response $context 403 '{"error":"Local access only."}'; continue
            }
            if ($request.HttpMethod -eq 'GET' -and $path -eq '/api/status') {
                Send-Response $context 200 (@{app='disguise-device-monitor-v2'; view=$script:view; devices=$script:results; intervalSeconds=10; serverTime=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5 -Compress)
            } elseif ($request.HttpMethod -eq 'POST' -and $path -in @('/api/devices','/api/check','/api/stop','/api/view','/api/fit')) {
                $origin = $request.Headers['Origin']
                if ($request.Headers['X-Device-Monitor'] -ne '1' -or ($origin -and $origin -ne "http://localhost:$HttpPort")) {
                    Send-Response $context 403 '{"error":"Open the local Device Monitor panel to make changes."}'; continue
                }
                if ($path -in @('/api/view','/api/fit')) {
                    if($request.ContentLength64 -lt 0 -or $request.ContentLength64 -gt 4096){throw 'Invalid request size'}
                    $reader=New-Object IO.StreamReader($request.InputStream);try{$read=$reader.ReadToEndAsync();if(!$read.Wait(2000)){throw 'Request timed out'};$body=$read.Result|ConvertFrom-Json}finally{$reader.Dispose()}
                    if($path -eq '/api/view'){
                        if($body.size -notin @('compact','standard','large') -or $body.columns -notin @(1,2,4)){Send-Response $context 400 '{"error":"Invalid layout"}';continue}
                        $next=@{size=$body.size;columns=[int]$body.columns};$tmp=$viewPath+'.tmp';[IO.File]::WriteAllText($tmp,($next|ConvertTo-Json));if(Test-Path $viewPath){[IO.File]::Replace($tmp,$viewPath,$viewPath+'.bak')}else{[IO.File]::Move($tmp,$viewPath)};$script:view=$next
                    }else{
                        $d=Dimensions ($body.settings -eq $true);$vw=[int]$body.width;$vh=[int]$body.height;$ch=[int]$body.content
                        if($vw -lt 100 -or $vw -gt 10000 -or $vh -lt 100 -or $ch -lt 50 -or $ch -gt 10000){throw 'Invalid dimensions'}
                        $fit=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fit-window.py')).Replace('{{WIDTH}}',[string]$d[0]).Replace('{{HEIGHT}}',[string]$d[1]).Replace('{{VW}}',[string]$vw).Replace('{{VH}}',[string]$vh).Replace('{{CH}}',[string]$ch).Replace('{{SETTINGS}}',$(if($body.settings){'True'}else{'False'}))
                        try{$r=Invoke-RestMethod 'http://127.0.0.1/api/session/python/execute' -Method Post -ContentType application/json -Body (@{script=$fit}|ConvertTo-Json -Compress) -TimeoutSec 2}catch{}
                    }
                } elseif ($path -eq '/api/devices') {
                    if ($request.ContentLength64 -lt 0 -or $request.ContentLength64 -gt 1048576) { Send-Response $context 413 '{"error":"Settings request exceeds 1 MB."}'; continue }
                    $reader = New-Object IO.StreamReader($request.InputStream, [Text.Encoding]::UTF8)
                    try {
                        $read = $reader.ReadToEndAsync()
                        if (-not $read.Wait(2000)) { throw 'Settings request timed out.' }
                        if (-not $read.Result.TrimStart().StartsWith('[')) { throw 'Settings must be a list of devices.' }
                        $clean = Validate-Devices (ConvertFrom-Json -InputObject $read.Result)
                    } catch {
                        Send-Response $context 400 (@{error=$_.Exception.Message} | ConvertTo-Json -Compress); continue
                    } finally { $reader.Dispose() }
                    $temp = "$configPath.tmp"
                    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $clean -Depth 4), (New-Object Text.UTF8Encoding($false)))
                    if (Test-Path -LiteralPath $configPath) {
                        [IO.File]::Replace($temp, $configPath, "$configPath.bak")
                    } else { [IO.File]::Move($temp,$configPath) }
                    $script:devices=$clean
                    Reset-Results
                } elseif ($path -eq '/api/check') {
                    $script:nextCheck=[DateTime]::UtcNow
                } else { $script:running=$false }
                Send-Response $context 200 '{"ok":true}'
            } elseif ($request.HttpMethod -eq 'GET' -and $path -in @('/','/index.html','/app.js','/style.css')) {
                $file = @{ '/'='index.html'; '/index.html'='index.html'; '/app.js'='app.js'; '/style.css'='style.css' }[$path]
                $type = @{ 'index.html'='text/html; charset=utf-8'; 'app.js'='text/javascript; charset=utf-8'; 'style.css'='text/css; charset=utf-8' }[$file]
                $text=Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw -Encoding UTF8
                if($file -eq 'index.html'){$d=Dimensions;$text=$text.Replace('{{SIZE}}',($d -join ','))}
                Send-Response $context 200 $text $type
            } else { Send-Response $context 404 '{"error":"Not found."}' }
        } catch {
            try { Send-Response $context 500 '{"error":"Monitor error. Check monitor.log and folder write permissions."}' } catch {}
            Add-Content -LiteralPath (Join-Path $PSScriptRoot 'monitor.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
        }
    }
} catch {
    Add-Content -LiteralPath (Join-Path $PSScriptRoot 'monitor.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
    exit 1
} finally {
    $listener.Close()
    foreach ($job in $script:jobs) { $job.ping.Dispose() }
}
