<#
.SYNOPSIS
    Removes the ArchonLauncher scheduled task and stops the watcher.

.PARAMETER TaskName
    Scheduled task name. Default "ArchonLauncher".

.PARAMETER KeepFiles
    Leave %LOCALAPPDATA%\ArchonLauncher (script and log) in place.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
#>
[CmdletBinding()]
param(
    [string] $TaskName = 'ArchonLauncher',
    [switch] $KeepFiles
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'ArchonLauncher'

Write-Host "Removing ArchonLauncher..." -ForegroundColor Cyan

# ------------------------------------------------------------ the task ------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch {}
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "  task removed: $TaskName"
} else {
    Write-Host "  no scheduled task named '$TaskName'"
}

# ------------------------------------------------- any running watcher ------
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*ArchonLauncher.ps1*' -and $_.ProcessId -ne $PID }

if ($running) {
    foreach ($p in $running) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  stopped watcher (pid $($p.ProcessId))"
    }
} else {
    Write-Host "  no watcher process running"
}

# ------------------------------------------------------------- the files ----
if ($KeepFiles) {
    Write-Host "  files kept at $installDir"
} elseif (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
    Write-Host "  files removed: $installDir"
}

Write-Host ""
Write-Host "Done. Archon's own settings were not touched." -ForegroundColor Green
