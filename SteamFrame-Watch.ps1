# Starts via Windows Task Scheduler at boot as SYSTEM.
# Uses Win32_DeviceChangeEvent and periodic fallback checks; applies once per plug-in.
$ErrorActionPreference = 'Stop'
$vidpid = 'USB\VID_28DE&PID_2432\'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$worker = Join-Path $root 'SteamFrame-6GHz.ps1'
$log = Join-Path $root 'SteamFrame-Watch.log'
$maxLogBytes = 2MB
function Log([string]$msg) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt $maxLogBytes) {
        Move-Item $log ($log + '.old') -Force
    }
    Add-Content -LiteralPath $log -Value ('{0:u} {1}' -f (Get-Date), $msg)
}
function DevicePresent {
    # Only match the specific Valve USB VID/PID and driver description.
    $dev = Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId.StartsWith($vidpid, [StringComparison]::OrdinalIgnoreCase) -and $_.FriendlyName -like '*8832CU*Valve*' -and $_.Status -eq 'OK' } |
        Select-Object -First 1
    return $null -ne $dev
}
function RunOnce {
    Log 'Adapter detected; applying country command.'
    # Existing script is not modified during execution; output is logged.
    try {
        $output = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -ApplyUS -Force 2>&1
        foreach ($line in $output) { Log ([string]$line) }
        Log ('Worker exit code: ' + $LASTEXITCODE)
    } catch { Log ('Worker failed: ' + $_.Exception.Message) }
}
Log 'Watcher started.'
$wasPresent = $false
Register-WmiEvent -Query 'SELECT * FROM Win32_DeviceChangeEvent WHERE EventType = 2 OR EventType = 3' -SourceIdentifier 'SteamFrameUsbChange' | Out-Null
try {
    while ($true) {
        # Boot/restart: apply once when the driver becomes ready.
        # Insertion/removal: event wakes loop; timeout is safety fallback.
        $present = DevicePresent
        if ($present -and -not $wasPresent) {
            RunOnce
        }
        $wasPresent = $present
        $event = Wait-Event -SourceIdentifier 'SteamFrameUsbChange' -Timeout 5
        if ($null -ne $event) {
            Remove-Event -EventIdentifier $event.EventIdentifier
            # Let PnP finish initializing before checking readiness.
            Start-Sleep -Seconds 2
        }
    }
} finally {
    Unregister-Event -SourceIdentifier 'SteamFrameUsbChange' -ErrorAction SilentlyContinue
}
