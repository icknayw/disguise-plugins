$ErrorActionPreference='Stop'
$config=Get-Content (Join-Path $PSScriptRoot 'plugin-config.json') -Raw|ConvertFrom-Json
$url='http://127.0.0.1:'+ $config.port
try{$health=Invoke-RestMethod ($url+'/api/state') -TimeoutSec 2}catch{$health=$null}
if($health){if($health.app -eq $config.id){exit 0};throw 'Port belongs to another application'}
$node=Join-Path $PSScriptRoot 'runtime\node.exe'
if(!(Test-Path $node)){$node='C:\Program Files\Companion\resources\node-runtimes\node22\node.exe'}
if(!(Test-Path $node)){$command=Get-Command node.exe -ErrorAction SilentlyContinue;if(!$command){throw 'Install Node.js 22 or Companion with Node 22'};$node=$command.Source}
$p=Start-Process -FilePath $node -ArgumentList ('"'+(Join-Path $PSScriptRoot 'server.mjs')+'"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'backend-output.log') -RedirectStandardError (Join-Path $PSScriptRoot 'backend-error.log')
$p.Id | Set-Content (Join-Path $PSScriptRoot 'helper.pid')
for($i=0;$i -lt 20;$i++){Start-Sleep -Milliseconds 200;try{$h=Invoke-RestMethod ($url+'/api/state') -TimeoutSec 1;if($h.app -eq $config.id){exit 0}}catch{}}
throw 'Helper failed to start. See backend-error.log.'
