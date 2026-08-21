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
    Seconds between checks. Default 1.

.PARAMETER LaunchDelaySeconds
    Seconds to wait after spotting the game before starting Archon. Default 3.
    Set to 0 to launch immediately.

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
    [int]    $LaunchDelaySeconds = -1,
    [switch] $QuitWithWow
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- defaults --
$cfg = @{
    ArchonExe          = ''
    GamePattern        = '^Wow(Classic|T|B)?$'
    PollSeconds        = 1
    LaunchDelaySeconds = 3
    QuitWithWow        = $false
    LogFile            = Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'
    MaxLogBytes        = 1MB
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
if ($LaunchDelaySeconds -ge 0)                     { $cfg.LaunchDelaySeconds = $LaunchDelaySeconds }
if ($QuitWithWow)                                  { $cfg.QuitWithWow = $true }

# ------------------------------------------------------------ sanity check --
# Start-Sleep -Seconds 0 returns instantly, which would spin a core at 100%.
# A negative value throws outright. Clamp both rather than trusting the file.
if ($cfg.PollSeconds        -lt 1) { $cfg.PollSeconds        = 1 }
if ($cfg.LaunchDelaySeconds -lt 0) { $cfg.LaunchDelaySeconds = 0 }

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

function Get-ArchonFromRegistry {
    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $keys) {
        $entries = Get-ItemProperty $k -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -match 'Archon App' }

        foreach ($e in $entries) {
            # Cleanest source, but Archon 9.6.0 ships this empty.
            if ($e.InstallLocation) {
                $c = Join-Path $e.InstallLocation 'Archon App.exe'
                if (Test-Path $c) { return $c }
            }
            # DisplayIcon is the executable followed by an icon index: "...\x.exe,0"
            if ($e.DisplayIcon) {
                $c = ($e.DisplayIcon -replace ',\s*\d+\s*$', '').Trim('"', ' ')
                if ($c -and $c -match '\.exe$' -and (Test-Path $c)) { return $c }
            }
            # UninstallString sits in the install directory alongside the app.
            if ($e.UninstallString) {
                $u = $e.UninstallString
                if ($u -match '^\s*"([^"]+)"') { $u = $matches[1] }
                else { $u = ($u -split '\s+/')[0].Trim() }
                if ($u) {
                    $dir = Split-Path $u -Parent
                    if ($dir) {
                        $c = Join-Path $dir 'Archon App.exe'
                        if (Test-Path $c) { return $c }
                    }
                }
            }
        }
    }
    return $null
}

function Get-ArchonFromRunningProcess {
    # If Archon happens to be running, its own image path is the ground truth --
    # useful when the registry no longer describes the install correctly.
    try {
        $p = Get-Process -ErrorAction SilentlyContinue |
             Where-Object { $_.ProcessName -like 'Archon*' } |
             Select-Object -First 1
        if ($p -and $p.Path -and (Test-Path $p.Path)) { return $p.Path }
    } catch {
        # Path is inaccessible for processes we cannot open; not fatal.
    }
    return $null
}

function Resolve-ArchonExe {
    param([string]$Configured)

    if ($Configured -and (Test-Path $Configured)) { return $Configured }

    $fromRegistry = Get-ArchonFromRegistry
    if ($fromRegistry) { return $fromRegistry }

    $fromProcess = Get-ArchonFromRunningProcess
    if ($fromProcess) { return $fromProcess }

    # Last resort: the locations Archon has historically installed itself to.
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

function Get-ExeNamePattern {
    param([string]$Path)
    '^' + [regex]::Escape([System.IO.Path]::GetFileNameWithoutExtension($Path)) + '$'
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
# Validate the pattern before the loop, or a typo throws once a second forever.
try {
    $null = [regex]::new($cfg.GamePattern)
} catch {
    Write-Log "FATAL: GamePattern is not a valid regex: $($cfg.GamePattern)"
    exit 1
}

$exe = Resolve-ArchonExe -Configured $cfg.ArchonExe
if (-not $exe) {
    Write-Log 'FATAL: could not locate "Archon App.exe" - set ArchonExe in config.json'
    exit 1
}

$archonPattern = Get-ExeNamePattern $exe

Write-Log "watcher started (pid $PID)"
Write-Log "archon    : $exe"
Write-Log "watching  : $($cfg.GamePattern)  every $($cfg.PollSeconds)s"
Write-Log "delay     : $($cfg.LaunchDelaySeconds)s after the game is spotted"
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
        if (Test-ProcessRunning $archonPattern) {
            Write-Log 'Archon already running - nothing to do'
        } else {
            if ($cfg.LaunchDelaySeconds -gt 0) {
                Write-Log "waiting $($cfg.LaunchDelaySeconds)s before launching"
                Start-Sleep -Seconds $cfg.LaunchDelaySeconds
            }
            # The game can disappear during the wait (crash, wrong client, instant alt-F4).
            if (-not (Test-ProcessRunning $cfg.GamePattern)) {
                Write-Log 'game gone during the delay - not launching'
            } else {
                # An Archon update can relocate the executable long after we
                # resolved it at startup, so re-resolve rather than launching a
                # path that is no longer there.
                if (-not (Test-Path $exe)) {
                    Write-Log "archon no longer at $exe - re-resolving"
                    $found = Resolve-ArchonExe -Configured $cfg.ArchonExe
                    if ($found) {
                        $exe = $found
                        $archonPattern = Get-ExeNamePattern $exe
                        Write-Log "archon    : $exe"
                    } else {
                        Write-Log 'FAILED: cannot locate Archon anywhere - skipping this launch'
                    }
                }

                if (Test-Path $exe) {
                    try {
                        Start-Process -FilePath $exe
                        Write-Log "launched $exe"
                    } catch {
                        Write-Log "launch FAILED: $_"
                    }
                }
            }
        }
    }
    elseif (-not $isRunning -and $wasRunning) {
        Write-Log 'game exited'
        if ($cfg.QuitWithWow) {
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessName -match $archonPattern } |
                ForEach-Object { $null = $_.CloseMainWindow() }
            Write-Log 'asked Archon to close'
        }
    }

    $wasRunning = $isRunning
}
