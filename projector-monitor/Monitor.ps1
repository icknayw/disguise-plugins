param([int]$HttpPort=18745,[switch]$TestMode)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
. (Join-Path $PSScriptRoot 'Slot.ps1')
$fleetPath=Join-Path $PSScriptRoot 'fleet.json'
$sizes=@{compact=@(230,114);standard=@(280,142);large=@(330,166)}
# Optional shared hosting. Default is loopback only.
$network=@{bindAddress='';allowedClients=@()}
$networkFile=Join-Path $PSScriptRoot 'network.json'
if(Test-Path $networkFile){$network=Get-Content $networkFile -Raw|ConvertFrom-Json}
$allowed=@($network.allowedClients)
$listener=New-Object Net.HttpListener
$running=$true
function Persist($view,$items){
 $data=@{version=2;view=$view;projectors=@($items|ForEach-Object {@{id=$_.id;config=$_.config}})}|ConvertTo-Json -Depth 8
 [IO.File]::WriteAllText($fleetPath+'.tmp',$data,(New-Object Text.UTF8Encoding($false)))
 for($attempt=0;$attempt -lt 5;$attempt++){
  try{if(Test-Path $fleetPath){[IO.File]::Replace($fleetPath+'.tmp',$fleetPath,[NullString]::Value)}else{[IO.File]::Move($fleetPath+'.tmp',$fleetPath)};break}catch{if($attempt -eq 4){throw};Start-Sleep -Milliseconds 100}
 }
}
function Dimensions($settings=$false){if($settings){return @(620,600)};$s=$sizes[$script:view.size];$cols=[Math]::Min([int]$script:view.columns,$script:slots.Count);$rows=[Math]::Ceiling($script:slots.Count/$cols);return @([int]($cols*$s[0]+($cols-1)*4+12),[int]($rows*$s[1]+($rows-1)*4+44))}
function Reply($ctx,$code,$body,$type='application/json; charset=utf-8'){
 $bytes=[Text.Encoding]::UTF8.GetBytes($body);$ctx.Response.StatusCode=$code;$ctx.Response.ContentType=$type;$ctx.Response.Headers['Cache-Control']='no-store'
 $ctx.Response.Headers['X-Content-Type-Options']='nosniff';$ctx.Response.Headers['Content-Security-Policy']="default-src 'self'; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'self'"
 $ctx.Response.ContentLength64=$bytes.Length;$ctx.Response.OutputStream.Write($bytes,0,$bytes.Length);$ctx.Response.Close()
}
function Read-Body($req){if($req.ContentLength64 -lt 0 -or $req.ContentLength64 -gt 20000){throw 'Invalid request size'};$r=New-Object IO.StreamReader($req.InputStream);try{$task=$r.ReadToEndAsync();if(!$task.Wait(2000)){throw 'Request timed out'};return $task.Result|ConvertFrom-Json}finally{$r.Dispose()}}
$script:view=@{size='compact';columns=2}
$script:slots=@()
if(Test-Path $fleetPath){
 $saved=Get-Content $fleetPath -Raw|ConvertFrom-Json
 if(!$sizes.ContainsKey([string]$saved.view.size) -or [int]$saved.view.columns -notin @(1,2,4) -or @($saved.projectors).Count -lt 1 -or @($saved.projectors).Count -gt 12){throw 'Invalid saved layout'}
 $script:view=@{size=$saved.view.size;columns=[int]$saved.view.columns}
 foreach($p in $saved.projectors){$c=@{};foreach($field in $p.config.PSObject.Properties){$c[$field.Name]=$field.Value};$script:slots+=New-Slot $p.id $c}
}else{
 foreach($entry in @(@('pj1','settings.json'),@('pj2','projector2/settings.json'))){
  $path=Join-Path $PSScriptRoot $entry[1]
  if(Test-Path $path){$c=@{};$saved=Get-Content $path -Raw|ConvertFrom-Json;foreach($field in $saved.PSObject.Properties){$c[$field.Name]=$field.Value};$script:slots+=New-Slot $entry[0] $c}
 }
 if(!$script:slots.Count){$script:slots=@((New-Slot 'pj1' @{name='Projector 1';ip='';port=1024;username='dispadmin';passwordProtected=''}))}
 Persist $script:view $script:slots
}
$listener.Prefixes.Add("http://localhost:$HttpPort/")
if(!$TestMode -and $network.bindAddress){$listener.Prefixes.Add("http://$($network.bindAddress):$HttpPort/")}
$listener.Start();$pending=$listener.GetContextAsync()
try{while($running){
 if(!$TestMode){foreach($slot in $script:slots){Update-Projector $slot}}
 if(!$pending.IsCompleted){Start-Sleep -Milliseconds 30;continue}
 $ctx=$pending.GetAwaiter().GetResult();$pending=$listener.GetContextAsync();$req=$ctx.Request;$path=$req.Url.AbsolutePath
 try{
  if(![Net.IPAddress]::IsLoopback($req.RemoteEndPoint.Address) -and $req.RemoteEndPoint.Address.ToString() -notin $allowed){Reply $ctx 403 '{"error":"Access denied"}';continue}
  if($req.HttpMethod -eq 'GET' -and $path -eq '/api/status'){
   $public=@(foreach($slot in $script:slots){@{id=$slot.id;config=(Public-Config $slot);status=$slot.status;checking=[bool]$slot.worker;control=$slot.control}})
   Reply $ctx 200 (@{app='disguise-projector-monitor-v2';view=$script:view;projectors=$public}|ConvertTo-Json -Depth 9 -Compress);continue
  }
  if($req.HttpMethod -eq 'POST'){
   $origins=@("http://localhost:$HttpPort")
   if($network.bindAddress){$origins+="http://$($network.bindAddress):$HttpPort"}
   if($req.Headers['X-Projector-Monitor'] -ne '1' -or ($req.Headers['Origin'] -and $req.Headers['Origin'] -notin $origins)){Reply $ctx 403 '{"error":"Use the monitor page"}';continue}
   if($path -eq '/api/stop'){$running=$false;Reply $ctx 200 '{"ok":true}';continue}
   $body=Read-Body $req
   if($path -eq '/api/layout'){
    if(@($script:slots|Where-Object {$_.controlWorker}).Count){throw 'Wait for the active command to finish'}
    if(!$sizes.ContainsKey([string]$body.size) -or [int]$body.columns -notin @(1,2,4) -or $body.projectors -isnot [Array] -or $body.projectors.Count -lt 1 -or $body.projectors.Count -gt 12){throw 'Choose 1 to 12 projectors and a valid layout'}
    $next=@();$seen=@{}
    foreach($p in $body.projectors){
     if($p.id -isnot [string] -or $p.id -notmatch '^[a-zA-Z0-9-]{1,80}$' -or $seen.ContainsKey($p.id)){throw 'Invalid projector ID'};$seen[$p.id]=$true
     $old=@($script:slots|Where-Object {$_.id -eq $p.id})|Select-Object -First 1
     $next+=New-Slot $p.id (Validate-Config $p $old.config)
    }
    $newView=@{size=$body.size;columns=[int]$body.columns};Persist $newView $next
    foreach($slot in $script:slots){Stop-Slot $slot};$script:slots=$next;$script:view=$newView
    Reply $ctx 200 '{"ok":true}';continue
   }
   if($path -eq '/api/fit'){
    if($body.view -notin @('monitor','settings')){throw 'Invalid view'};$d=Dimensions ($body.view -eq 'settings')
    $fit=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fit-window.py')).Replace('{{WIDTH}}',[string]$d[0]).Replace('{{HEIGHT}}',[string]$d[1]).Replace('{{PATH}}',$(if($body.view -eq 'settings'){'/settings'}else{'/'}))
    $vw=[int]$body.viewportWidth;$vh=[int]$body.viewportHeight;$ch=[int]$body.contentHeight
    if($vw -lt 100 -or $vw -gt 10000 -or $vh -lt 100 -or $vh -gt 10000 -or $ch -lt 50 -or $ch -gt 10000){$vw=0;$vh=0;$ch=0}
    $fit=$fit.Replace('{{VW}}',[string]$vw).Replace('{{VH}}',[string]$vh).Replace('{{CH}}',[string]$ch)
    $target=if([Net.IPAddress]::IsLoopback($req.RemoteEndPoint.Address)){'127.0.0.1'}else{$req.RemoteEndPoint.Address.ToString()}
    try{if($TestMode){throw 'Test mode'};$r=Invoke-RestMethod "http://$target/api/session/python/execute" -Method Post -ContentType 'application/json' -Body (@{script=$fit}|ConvertTo-Json -Compress) -TimeoutSec 2
     Reply $ctx 200 $(if($r.returnValue -is [string]){$r.returnValue}else{$r.returnValue|ConvertTo-Json -Compress})}catch{Reply $ctx 200 '{"resized":0}'};continue
   }
   if($path -match '^/api/projectors/([a-zA-Z0-9-]+)/(?<operation>check|control)$'){
    $id=$Matches[1];$op=$Matches.operation;$slot=@($script:slots|Where-Object {$_.id -eq $id})|Select-Object -First 1
    if(!$slot){Reply $ctx 404 '{"error":"Projector removed"}';continue};$config=$slot.config;$status=$slot.status
    if($op -eq 'check'){$slot.nextCheck=[DateTime]::UtcNow;Reply $ctx 200 '{"ok":true}';continue}
    if($body.action -notin @('power-on','power-off','shutter-open','shutter-close') -or $body.id -isnot [string] -or $body.id -notmatch '^[a-zA-Z0-9-]{8,80}$'){throw 'Invalid command'}
    if($slot.requests.ContainsKey($body.id)){Reply $ctx 200 ($slot.requests[$body.id]|ConvertTo-Json -Compress);continue}
    if($TestMode){Reply $ctx 409 '{"error":"Controls disabled in test mode"}';continue}
    if($slot.controlWorker){Reply $ctx 409 '{"error":"Command already running"}';continue}
    if($body.ip -ne $config.ip -or $body.port -ne $config.port){Reply $ctx 409 '{"error":"Settings changed. Refresh first"}';continue}
    if($status.connection -notin @('online','partial') -or !$status.checkedAt -or ([DateTime]::UtcNow-[DateTime]::Parse($status.checkedAt).ToUniversalTime()).TotalSeconds -gt 25){Reply $ctx 409 '{"error":"Wait for current projector status"}';continue}
    # Request IDs make retries idempotent; only recent ones need remembering.
    if($slot.requests.Count -ge 32){$slot.requests.Clear()}
    $slot.control=@{id=$body.id;action=$body.action;state='pending';message='Sending command'};$slot.requests[$body.id]=$slot.control;$slot.generation++
    $password=Get-Password $config;$slot.controlWorker=Start-Worker $slot $password $body.action;$password=$null
    Add-Content (Join-Path $PSScriptRoot 'controls.jsonl') (@{at=[DateTime]::UtcNow.ToString('o');projector=$slot.id;action=$body.action;id=$body.id;source=$req.RemoteEndPoint.Address.ToString()}|ConvertTo-Json -Compress)
    Reply $ctx 202 ($slot.control|ConvertTo-Json -Compress);continue
   }
  }
  if($req.HttpMethod -eq 'GET' -and $path -in @('/','/settings','/app.js','/style.css')){
   $file=if($path -in @('/','/settings')){'index.html'}else{$path.Substring(1)};$text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $file))
   if($file -eq 'index.html'){$d=Dimensions ($path -eq '/settings');$text=$text.Replace('{{SIZE}}',($d -join ','))}
   $type=if($file -eq 'app.js'){'text/javascript'}elseif($file -eq 'style.css'){'text/css'}else{'text/html'};Reply $ctx 200 $text ($type+'; charset=utf-8');continue
  }
  Reply $ctx 404 '{"error":"Not found"}'
 }catch{try{Reply $ctx 400 (@{error=$_.Exception.Message}|ConvertTo-Json -Compress)}catch{}}
}}finally{$listener.Close();foreach($slot in $script:slots){Stop-Slot $slot}}
