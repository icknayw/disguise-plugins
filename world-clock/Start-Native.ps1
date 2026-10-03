$ErrorActionPreference='Stop'
try{$h=Invoke-RestMethod 'http://127.0.0.1:18753/api/state' -TimeoutSec 2}catch{$h=$null}
if($h){if($h.app -eq 'world-clock'){exit 0};throw 'Port 18753 belongs to another application'}
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $ps -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $PSScriptRoot 'Serve.ps1')+'"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $PSScriptRoot 'backend-output.log') -RedirectStandardError (Join-Path $PSScriptRoot 'backend-error.log')
for($i=0;$i -lt 20;$i++){Start-Sleep -Milliseconds 200;try{$h=Invoke-RestMethod 'http://127.0.0.1:18753/api/state' -TimeoutSec 1;if($h.app -eq 'world-clock'){exit 0}}catch{}}
throw 'World Clock failed to start; see backend-error.log'
