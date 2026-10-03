$ErrorActionPreference='Stop'
$listener=New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://127.0.0.1:18753/')
$zones=Get-Content (Join-Path $PSScriptRoot 'timezones.json') -Raw|ConvertFrom-Json
$sizes=@{compact=@(242,46);standard=@(292,58);large=@(342,76)}
$settingsFile=Join-Path $PSScriptRoot 'clock-settings.json'
function Valid($c){return ($null -ne $c -and $sizes.ContainsKey([string]$c.size) -and $c.zones -is [Array] -and $c.zones.Count -ge 1 -and $c.zones.Count -le 8 -and @($c.zones|Where-Object {$zones -notcontains $_}).Count -eq 0)}
function Settings {try{$c=Get-Content $settingsFile -Raw|ConvertFrom-Json;if(Valid $c){return $c}}catch{};return @{size='compact';zones=@('Asia/Tokyo','Europe/London','America/New_York')}}
$listener.Start()
try {while($listener.IsListening){
 $ctx=$listener.GetContext();$res=$ctx.Response;$req=$ctx.Request;$res.Headers.Add('Cache-Control','no-store');$res.ContentType='application/json; charset=utf-8'
 try {
  $path=$req.Url.AbsolutePath;$content=$null
  if($path -eq '/api/fit' -and $req.HttpMethod -eq 'POST'){
   if($req.Headers['Origin'] -ne ('http://'+$req.UserHostName) -or $req.ContentLength64 -lt 0 -or $req.ContentLength64 -gt 128){$res.StatusCode=403;$content='{"error":"Invalid fit request"}'}
   else{
    $reader=New-Object IO.StreamReader($req.InputStream);$body=$reader.ReadToEnd()|ConvertFrom-Json;$reader.Dispose()
    if($body.view -notin @('clock','settings')){throw 'Invalid view'}
    $c=Settings;$sz=$sizes[$c.size];$width=if($body.view -eq 'settings'){360}else{$sz[0]};$height=if($body.view -eq 'settings'){410}else{$c.zones.Count*$sz[1]+($c.zones.Count-1)*4+40};$page=if($body.view -eq 'settings'){'/settings'}else{'/'}
    $script=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fit-window.py')).Replace('{{WIDTH}}',[string]$width).Replace('{{HEIGHT}}',[string]$height).Replace('{{PATH}}',$page)
    try{$r=Invoke-RestMethod 'http://127.0.0.1/api/session/python/execute' -Method Post -ContentType 'application/json' -Body (@{script=$script}|ConvertTo-Json -Compress) -TimeoutSec 3;$content=$r.returnValue}catch{$content='{"resized":0}'}
   }
  }elseif($path -eq '/api/settings' -and $req.HttpMethod -eq 'POST'){
   if($req.Headers['Origin'] -ne ('http://'+$req.UserHostName) -or $req.ContentType.Split(';')[0] -ne 'application/json'){$res.StatusCode=403;$content='{"error":"Open settings from this server"}'}
   elseif($req.ContentLength64 -lt 0 -or $req.ContentLength64 -gt 4096){$res.StatusCode=413;$content='{"error":"Request too large"}'}
   else{
    $reader=New-Object IO.StreamReader($req.InputStream);try{$body=$reader.ReadToEnd()|ConvertFrom-Json}catch{$body=$null};$reader.Dispose()
    if(!(Valid $body)){$res.StatusCode=400;$content='{"error":"Choose 1 to 8 valid timezones and a size"}'}
    else{$data=@{size=$body.size;zones=@($body.zones)}|ConvertTo-Json -Compress;[IO.File]::WriteAllText($settingsFile+'.tmp',$data,(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath ($settingsFile+'.tmp') -Destination $settingsFile -Force;$content='{"ok":true}'}
   }
  }elseif($req.HttpMethod -ne 'GET'){$res.StatusCode=405;$content='{"error":"Method not allowed"}'}
  elseif($path -eq '/api/state'){$content='{"app":"world-clock"}'}
  elseif($path -eq '/api/settings'){$content=Settings|ConvertTo-Json -Compress}
  elseif($path -eq '/' -or $path -eq '/settings'){
   $c=Settings;$s=$sizes[$c.size];$dim=if($path -eq '/settings'){'360,410'}else{[string]$s[0]+','+[string]($c.zones.Count*$s[1]+($c.zones.Count-1)*4+40)}
   $res.ContentType='text/html; charset=utf-8';$content=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'index.html')).Replace('{{SIZE}}',$dim)
  }else{
   $files=@{'/clock.js'=@('clock.js','text/javascript');'/style.css'=@('style.css','text/css');'/timezones.json'=@('timezones.json','application/json')};$f=$files[$path]
   if(!$f){$res.StatusCode=404;$content='{"error":"Not found"}'}else{$res.ContentType=$f[1]+'; charset=utf-8';$content=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $f[0]))}
  }
  $bytes=[Text.Encoding]::UTF8.GetBytes($content)
 }catch{$res.StatusCode=500;$bytes=[Text.Encoding]::UTF8.GetBytes((@{error=$_.Exception.Message}|ConvertTo-Json -Compress))}
 try{$res.ContentLength64=$bytes.Length;$res.OutputStream.Write($bytes,0,$bytes.Length)}finally{$res.Close()}
}}finally{$listener.Stop();$listener.Close()}

