$server=(Join-Path $PSScriptRoot 'server.mjs').ToLowerInvariant()
$native=(Join-Path $PSScriptRoot 'Serve.ps1').ToLowerInvariant()
Get-CimInstance Win32_Process | Where-Object {($_.Name -eq 'node.exe' -or $_.Name -eq 'powershell.exe') -and $_.CommandLine -and ($_.CommandLine.ToLowerInvariant().Contains($server) -or $_.CommandLine.ToLowerInvariant().Contains($native))} | ForEach-Object {Stop-Process -Id $_.ProcessId}
