$ErrorActionPreference = 'Stop'
Invoke-RestMethod 'http://localhost:18743/api/stop' -Method Post -Headers @{'X-Device-Monitor'='1'} | Out-Null
Write-Host 'Device Monitor stopped.'
