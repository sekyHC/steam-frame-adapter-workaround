# Run once from an elevated Windows PowerShell console.
# Installs a boot task as LOCAL SYSTEM; no external executable or downloads.
$ErrorActionPreference = 'Stop'
$taskName = 'Steam Frame 6GHz - USB watcher'
$installDir = Join-Path $env:ProgramData 'SteamFrame6GHz'
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell as Administrator.'
}
foreach ($name in @('SteamFrame-6GHz.ps1','SteamFrame-Watch.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $name))) { throw "Missing $name alongside installer." }
}
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
foreach ($name in @('SteamFrame-6GHz.ps1','SteamFrame-Watch.ps1')) {
    Copy-Item -LiteralPath (Join-Path $sourceDir $name) -Destination (Join-Path $installDir $name) -Force
}
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $installDir 'SteamFrame-Watch.ps1'))
$trigger = New-ScheduledTaskTrigger -AtStartup
$account = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $account -Settings $settings -Description 'Detect Valve USB VID_28DE PID_2432 at boot and on connection; run 6 GHz Realtek command once per insertion.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "Installed task: $taskName"
Write-Host "Scripts and log: $installDir"
Write-Host 'Task started. Inspect SteamFrame-Watch.log to check driver replies.'
Write-Warning 'This uses the unverified WlanIhvControl command script. Do not assume it worked until the log confirms it.'
