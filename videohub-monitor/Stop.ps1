$ErrorActionPreference='Stop'
$pidFile=Join-Path $PSScriptRoot 'helper.pid'
if(!(Test-Path $pidFile)){Write-Host 'No helper PID saved';exit}
$helperPid=[int](Get-Content $pidFile)
$p=Get-CimInstance Win32_Process -Filter "ProcessId=$helperPid"
$expected=Join-Path $PSScriptRoot 'server.mjs'
if($p -and $p.Name -eq 'node.exe' -and $p.CommandLine.Contains($expected)){Stop-Process -Id $helperPid;Remove-Item -LiteralPath $pidFile}else{throw 'PID does not match this helper. Nothing stopped.'}
