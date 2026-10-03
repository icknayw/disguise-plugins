$ErrorActionPreference = 'Stop'
$server = Join-Path $PSScriptRoot 'Monitor.ps1'
try {
    $health = Invoke-RestMethod 'http://localhost:18743/api/status' -TimeoutSec 2
    if ($health.app -eq 'disguise-device-monitor-v2') { Write-Host 'Device Monitor is already running.'; exit }
    throw 'Port 18743 is occupied by a different application.'
} catch {
    if ($_.Exception.Message -like '*different application*') { throw }
}
$process = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $server))
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Milliseconds 200
    try {
        $health = Invoke-RestMethod 'http://localhost:18743/api/status' -TimeoutSec 1
        if ($health.app -eq 'disguise-device-monitor-v2') { Write-Host 'Device Monitor ready at http://localhost:18743/'; exit }
    } catch {}
    if ($process.HasExited) { break }
}
throw "Device Monitor could not start. See $(Join-Path $PSScriptRoot 'monitor.log')."
