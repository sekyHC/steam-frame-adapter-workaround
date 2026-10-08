$ErrorActionPreference = 'Stop'
$taskName = 'Steam Frame 6GHz - USB watcher'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Write-Host 'Task removed. Logs and scripts remain in C:\ProgramData\SteamFrame6GHz and may be deleted manually.'
