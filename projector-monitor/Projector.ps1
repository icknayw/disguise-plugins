# Runs only on a background PowerShell runspace.
param([ValidateSet('panasonic','epson')][string]$Brand='panasonic',[string]$Address,[int]$Port,[string]$Username,[string]$Password,[string]$Action='')
$ErrorActionPreference='Stop'
# Each driver defines Send-Control and Read-Status using $Address, $Port, $Username and $Password.
. (Join-Path $PSScriptRoot @{panasonic='Panasonic.ps1';epson='Epson.ps1'}[$Brand])

# Driver errors safe to show as-is. Anything else is reported generically.
$authErrors='Login rejected|Password required|Unsupported projector authentication'

if ($Action) {
    if ($Action -notin @('power-on','power-off','shutter-open','shutter-close')) { return @{ok=$false;error='Control not allowed.'} }
    try {
        Send-Control $Action
        return @{ok=$true;error=''}
    } catch {
        if ($_.Exception.Message -match "$authErrors|rejected the command|Unexpected acknowledgement") {return @{ok=$false;error=$_.Exception.Message}}
        return @{ok=$false;error='No acknowledgement. Check status before retrying.'}
    } finally {$Password=$null}
}

$result=@{connection='offline'; checkedAt=$null; error=''; model=$null; serial=$null; power=$null; shutter=$null; input=$null; freeze=$null; signal=$null; fault=$null; intakeC=$null; exhaustC=$null; projectorHours=$null; lightHours=$null; firmware=$null}
try {
    Read-Status $result
} catch {
    $message=$_.Exception.Message
    if ($message -match 'Login rejected|Password required') {$result.connection='auth'; $result.error=$message}
    elseif ($message -match 'Unsupported projector authentication') {$result.connection='error'; $result.error=$message}
    elseif ($result.connection -eq 'online') {$result.connection='partial'; $result.error='Incomplete status. Retrying.'}
    else {$result.connection='offline'; $result.error='No response on control port '+$Port+'.'}
} finally { $Password=$null }
$result.checkedAt=[DateTime]::UtcNow.ToString('o')
return $result
