<#
.SYNOPSIS
    Starts the Archon App when World of Warcraft launches.

.DESCRIPTION
    Archon's built-in "launch with game" setting only opens the window of an
    already-running instance -- there is no resident component to cold-start it.
    This watcher fills that gap: it polls for the WoW process and starts Archon
    when it appears.

    Settings are read from config.json next to this script, if present.
    Command-line parameters override config.json, which overrides the defaults.

.PARAMETER ArchonExe
    Full path to "Archon App.exe". Auto-detected if omitted.

.PARAMETER GamePattern
    Regex matched against process names (no .exe). Default covers retail,
    Classic, PTR and beta.

.PARAMETER PollSeconds
    Seconds between checks. Default 5.

.PARAMETER QuitWithWow
    Also close Archon when WoW exits.

.EXAMPLE
    .\ArchonLauncher.ps1
    .\ArchonLauncher.ps1 -GamePattern '^Wow$' -QuitWithWow
#>
[CmdletBinding()]
param(
    [string] $ArchonExe,
    [string] $GamePattern,
    [int]    $PollSeconds,
    [switch] $QuitWithWow
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- defaults --
$cfg = @{
    ArchonExe   = ''
    GamePattern = '^Wow(Classic|T|B)?$'
    PollSeconds = 5
    QuitWithWow = $false
    LogFile     = Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'
    MaxLogBytes = 1MB
}

# ------------------------------------------------------------- config.json --
$configPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $configPath) {
    try {
        $fromFile = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($p in $fromFile.PSObject.Properties) {
            if ($cfg.ContainsKey($p.Name) -and $null -ne $p.Value -and "$($p.Value)" -ne '') {
                $cfg[$p.Name] = $p.Value
            }
        }
    } catch {
        # A malformed config must not stop the watcher from running.
        Write-Warning "ignoring unreadable config.json: $_"
    }
}

# ------------------------------------------------- parameter overrides ------
if ($PSBoundParameters.ContainsKey('ArchonExe'))   { $cfg.ArchonExe   = $ArchonExe }
if ($PSBoundParameters.ContainsKey('GamePattern')) { $cfg.GamePattern = $GamePattern }
if ($PSBoundParameters.ContainsKey('PollSeconds')) { $cfg.PollSeconds = $PollSeconds }
if ($QuitWithWow)                                  { $cfg.QuitWithWow = $true }

New-Item -ItemType Directory -Force -Path (Split-Path $cfg.LogFile) | Out-Null

# ------------------------------------------------------------------- utils --
function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Write-Verbose $line
    try {
        $item = Get-Item $cfg.LogFile -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt $cfg.MaxLogBytes) {
            Move-Item $cfg.LogFile "$($cfg.LogFile).1" -Force
        }
        Add-Content -Path $cfg.LogFile -Value $line -Encoding utf8
    } catch {
        # Never let logging failures kill the loop.
    }
}

function Resolve-ArchonExe {
    param([string]$Configured)

    if ($Configured -and (Test-Path $Configured)) { return $Configured }

    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $keys) {
        $entry = Get-ItemProperty $k -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -match 'Archon App' -and $_.InstallLocation } |
                 Select-Object -First 1
        if ($entry) {
            $candidate = Join-Path $entry.InstallLocation 'Archon App.exe'
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $fallbacks = @(
        (Join-Path $env:ProgramFiles        'Archon App\Archon App.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Archon App\Archon App.exe'),
        (Join-Path $env:LOCALAPPDATA        'Programs\Archon App\Archon App.exe')
    )
    foreach ($f in $fallbacks) {
        if ($f -and (Test-Path $f)) { return $f }
    }

    return $null
}

function Test-ProcessRunning {
    param([string]$Pattern)
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.ProcessName -match $Pattern) { return $true }
    }
    return $false
}

# -------------------------------------------------------------------- main --
$exe = Resolve-ArchonExe -Configured $cfg.ArchonExe
if (-not $exe) {
    Write-Log 'FATAL: could not locate "Archon App.exe" - set ArchonExe in config.json'
    exit 1
}

Write-Log "watcher started (pid $PID)"
Write-Log "archon    : $exe"
Write-Log "watching  : $($cfg.GamePattern)  every $($cfg.PollSeconds)s"
if ($cfg.QuitWithWow) { Write-Log 'quit-with-wow: enabled' }

$wasRunning = Test-ProcessRunning $cfg.GamePattern
if ($wasRunning) { Write-Log 'game already running at startup - waiting for next launch' }

while ($true) {
    Start-Sleep -Seconds $cfg.PollSeconds

    try {
        $isRunning = Test-ProcessRunning $cfg.GamePattern
    } catch {
        Write-Log "process query failed: $_"
        continue
    }

    if ($isRunning -and -not $wasRunning) {
        Write-Log 'game detected'
        if (Test-ProcessRunning '^Archon App$') {
            Write-Log 'Archon already running - nothing to do'
        } else {
            try {
                Start-Process -FilePath $exe
                Write-Log "launched $exe"
            } catch {
                Write-Log "launch FAILED: $_"
            }
        }
    }
    elseif (-not $isRunning -and $wasRunning) {
        Write-Log 'game exited'
        if ($cfg.QuitWithWow) {
            Get-Process -Name 'Archon App' -ErrorAction SilentlyContinue |
                ForEach-Object { $null = $_.CloseMainWindow() }
            Write-Log 'asked Archon to close'
        }
    }

    $wasRunning = $isRunning
}
