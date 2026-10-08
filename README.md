# steam-frame-adapter-workaround

NOTE: applying a US regulatory profile outside US may enable radio settings that aren't legally permitted there.

This is same fix as https://github.com/toorux/steam-frame-6ghz-tool is doing, but my solution is automatic and doesn't require you to run unknown exe. This script is very easy to check with AI.

## Windows

### How it works
- On Windows startup: Waits for the Realtek adapter to become ready, then runs the country command.
- When the adapter is plugged in: Detects the USB device and runs the command.
- When it stays plugged in: Does not repeatedly send the command.
- When unplugged and reconnected: Runs it again after detecting a new connection.
It uses a Task Scheduler startup task running as SYSTEM, with a PowerShell watcher listening for device-change events and checking every five seconds as a fallback.

### Installation
1. Extract the ZIP.
2. Open PowerShell as Administrator.
3. Navigate to the extracted folder.
4. Execute:

```ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Install-SteamFrame-AutoRun.ps1"
```


The installer copies the scripts to:
```
C:\ProgramData\SteamFrame6GHz\
```


It also creates and starts the scheduled task.
Check whether it worked
Inspect the log:
```
Get-Content "C:\ProgramData\SteamFrame6GHz\SteamFrame-Watch.log" -Tail 30
```


The included SteamFrame-6GHz.ps1 has a -Force switch that bypasses its interactive confirmation for scheduled execution.
### Uninstall
Run PowerShell as Administrator:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Uninstall-SteamFrame-AutoRun.ps1"
```


## Frame

Make sure to change to US there as well.

To see current regulatory domain:

```sh
iw reg get
```

To set it to `US`:

```sh
sudo iw reg set US
```
