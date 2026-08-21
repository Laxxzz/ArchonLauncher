<#
.SYNOPSIS
    Installs ArchonLauncher as a hidden logon scheduled task for the current user.

.DESCRIPTION
    Copies the watcher into %LOCALAPPDATA%\ArchonLauncher, registers a scheduled
    task that starts it at logon, and starts it immediately.

    No administrator rights are required -- the task runs as the current user
    only. Re-running this script safely overwrites a previous install.

.PARAMETER TaskName
    Scheduled task name. Default "ArchonLauncher".

.PARAMETER QuitWithWow
    Also close Archon when WoW exits.

.PARAMETER HeartbeatMinutes
    How often Task Scheduler re-checks that the watcher is alive, restarting it
    if it isn't. Default 5.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install.ps1
#>
[CmdletBinding()]
param(
    [string] $TaskName = 'ArchonLauncher',
    [switch] $QuitWithWow,
    [int]    $HeartbeatMinutes = 5
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'ArchonLauncher'
$target     = Join-Path $installDir 'ArchonLauncher.ps1'
$source     = Join-Path $PSScriptRoot 'ArchonLauncher.ps1'
$shimSource = Join-Path $PSScriptRoot 'RunHidden.vbs'
$shimTarget = Join-Path $installDir 'RunHidden.vbs'

if (-not (Test-Path $source)) {
    throw "ArchonLauncher.ps1 not found next to this installer ($PSScriptRoot)"
}
if (-not (Test-Path $shimSource)) {
    throw "RunHidden.vbs not found next to this installer ($PSScriptRoot)"
}

Write-Host "Installing ArchonLauncher..." -ForegroundColor Cyan

# ------------------------------------------------------------ copy payload --
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item $source $target -Force
Write-Host "  script  -> $target"
Copy-Item $shimSource $shimTarget -Force
Write-Host "  shim    -> $shimTarget"

$srcCfg = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $srcCfg) {
    Copy-Item $srcCfg (Join-Path $installDir 'config.json') -Force
    Write-Host "  config  -> $installDir\config.json"
}

# --------------------------------------------------- stop any running copy --
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*ArchonLauncher.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object {
        Write-Host "  stopping running watcher (pid $($_.ProcessId))"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

# -------------------------------------------------------- register the task --
# Launch through the VBS shim rather than powershell.exe directly: Task
# Scheduler gives a console-subsystem process a console window every time it
# fires, which flashes on screen. wscript.exe starts PowerShell with no window
# at all. See the comments in RunHidden.vbs.
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

$argLine = "`"$shimTarget`""
if ($QuitWithWow) { $argLine += ' -QuitWithWow' }

$action = New-ScheduledTaskAction -Execute $wscript -Argument $argLine

# Two triggers, deliberately.
#
# Task Scheduler's "restart on failure" only covers a task that fails to START,
# not one whose process is killed later. Without a heartbeat, anything that
# terminates the watcher (a manual kill, a reinstall, an overzealous security
# tool) leaves it dead until the next logon -- silently.
#
# Attaching repetition to the logon trigger does NOT work: it only repeats
# within that trigger's own window and will not revive a task mid-session.
# An independent Once trigger with its own repetition does. MultipleInstances
# is IgnoreNew, so a heartbeat that fires while the watcher is healthy is a
# no-op.
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $HeartbeatMinutes))
)

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -Hidden

# The watcher is a long-running loop; without this the task is killed after 72h.
$settings.ExecutionTimeLimit = 'PT0S'

Register-ScheduledTask `
    -TaskName    $TaskName `
    -Action      $action `
    -Trigger     $triggers `
    -Principal   $principal `
    -Settings    $settings `
    -Description 'Starts the Archon App when World of Warcraft launches.' `
    -Force | Out-Null

Write-Host "  task    -> $TaskName (at logon, hidden, self-healing every ${HeartbeatMinutes}m)"

Start-ScheduledTask -TaskName $TaskName

# The shim exits as soon as it has spawned PowerShell, so the task returns to
# Ready immediately and its state says nothing about health. Check for the
# watcher process itself.
$watcher = $null
foreach ($attempt in 1..10) {
    Start-Sleep -Milliseconds 700
    $watcher = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*ArchonLauncher.ps1*' } |
               Select-Object -First 1
    if ($watcher) { break }
}

Write-Host ""
if ($watcher) {
    Write-Host "Installed and running." -ForegroundColor Green
    Write-Host "  watcher  : pid $($watcher.ProcessId)"
} else {
    Write-Host "Installed, but the watcher did not start." -ForegroundColor Yellow
    Write-Host "  check $installDir\launcher.log, then run this installer again."
}
Write-Host "  log      : $installDir\launcher.log"
Write-Host ""
Write-Host "Launch WoW to test. To remove: .\Uninstall.ps1" -ForegroundColor Cyan
