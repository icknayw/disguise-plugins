$ErrorActionPreference='Stop'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Start.ps1')
if($LASTEXITCODE -ne 0){throw 'Helper did not start'}
$c=Get-Content (Join-Path $PSScriptRoot 'd3plugin.json') -Raw|ConvertFrom-Json
$descriptor=@{name=$c.name;url=$c.url;type='web';requiresSession=$false;isDisguise=$false}|ConvertTo-Json -Compress
$script="import json`nfrom plugin import plugins_launcher as p`nwith p.UnrestrictedScope():`n p.openPlugin(json.loads('"+$descriptor+"'))`nreturn True"
Invoke-RestMethod 'http://127.0.0.1/api/session/python/execute' -Method Post -ContentType application/json -Body (@{script=$script}|ConvertTo-Json)
