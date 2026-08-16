# ArchonLauncher

Starts the [Archon App](https://www.archon.gg/) when World of Warcraft launches.

## The problem

Archon has a **"launch with game"** setting. It does not do what most people
assume: it only opens the window of an **already-running** Archon instance.

The handler behind that setting lives in the app's own UI layer. When it sees a
new game process, it waits a few seconds and then asks Archon's window manager
to open the main window — an operation on a window that already exists. It never
starts a process.

That code can only run if Archon is already running. And Archon ships no
service, no scheduled task, and no resident helper — the Overwolf
game-detection components (`gep`, `overlay`, `recorder`, `utility`) are loaded
*inside* `Archon App.exe` itself. So with Archon closed, nothing on the machine
is watching for the game, and nothing starts it.

You can confirm this in Archon's own log at
`%APPDATA%\Archon App\logs\main.log`: when the feature fires it records a window
action with the reason `Auto Launch on Game Start` — always in a session that
was already running.

The intended flow is that Archon runs from boot via its *Run on startup*
setting and sits in the tray all day. If you would rather it start only when
you actually play, that has to come from outside the app.

## What this does

A small PowerShell watcher, registered as a hidden logon task, checks once a
second for the WoW process and starts Archon when it appears — so Archon only
runs while you're actually playing.

It launches Archon normally, so Archon's own game-version detection, tooltips,
combat log upload and overlay all work exactly as usual.

### What it costs

Measured on a 16-core desktop with ~262 running processes, at the default
1-second interval, once past startup:

| | Watcher | Archon App idling |
| --- | --- | --- |
| Processes | 1 | 13 |
| Private memory | ~103 MB | ~1,622 MB |
| CPU | 94 ms per 20 s — 0.47% of one core, **0.029% of all cores** | — |

Each check takes roughly 4 ms to enumerate every process on the system. Raising
`PollSeconds` to `5` cuts the CPU by five times, to about 0.005% of all cores —
but both figures are far below the noise floor of normal desktop activity, so
pick the interval for responsiveness rather than for performance.

The memory is PowerShell's runtime rather than the script itself. It is roughly
a sixteenth of what Archon uses sitting idle, which is the trade this tool
exists to make.

## Install

No administrator rights needed, and no typing commands. The task runs as the
current user only.

1. Download the zip and **extract it** (right-click → Extract All). Don't run it
   from inside the zip.
2. Double-click **`Install.cmd`**.
3. Answer the one question it asks, and you're done.

Windows may show *"Windows protected your PC"* because the file came from the
internet. Click **More info → Run anyway**. The installer clears that mark from
the other files itself.

The installer copies the watcher to `%LOCALAPPDATA%\ArchonLauncher`, registers a
hidden logon task, and starts it immediately — no reboot required.

Double-click **`ViewLog.cmd`** any time to see what it has been doing.

### Command line

If you prefer it, or want to script the install:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1            # basic
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -QuitWithWow
```

## Uninstall

Double-click **`Uninstall.cmd`** and confirm.

Removes the task, stops the watcher, and deletes `%LOCALAPPDATA%\ArchonLauncher`.
Archon's own settings are never touched.

Command-line equivalent, with `-KeepFiles` to leave the folder in place:

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

## Configuration

Optional. Copy `config.example.json` to `config.json` next to
`ArchonLauncher.ps1` **before** running `Install.cmd`, and it gets installed
along with the script. Empty or missing values fall back to the defaults:

```json
{
  "ArchonExe":          "C:\\Program Files\\Archon App\\Archon App.exe",
  "GamePattern":        "^Wow(Classic|T|B)?$",
  "PollSeconds":        1,
  "LaunchDelaySeconds": 3,
  "QuitWithWow":        false
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `ArchonExe` | auto-detected | Path to `Archon App.exe`. Found via the uninstall registry entry, then the usual install locations. |
| `GamePattern` | `^Wow(Classic\|T\|B)?$` | Regex against process names, no `.exe`. Covers retail, Classic, PTR (`WowT`), beta (`WowB`). |
| `PollSeconds` | `1` | Seconds between checks. Minimum `1`. |
| `LaunchDelaySeconds` | `3` | Wait this long after spotting the game before starting Archon. `0` launches immediately. |
| `QuitWithWow` | `false` | Close Archon when the game exits. |

To watch retail only, set `GamePattern` to `^Wow$`.

### About the timing

The delay runs from when the watcher *spots* the game, not from the instant WoW
starts — those differ by up to `PollSeconds`. At the defaults that gap is at
most a second, so Archon appears **3–4 seconds** after you launch WoW.

Want it to wait longer before appearing? Raise `LaunchDelaySeconds`. Raising
`PollSeconds` instead makes the timing less predictable, since it widens the
window between the game starting and the watcher noticing.

## Verifying / troubleshooting

Double-click **`ViewLog.cmd`** — it shows recent activity and whether the task
is running. A healthy run looks like:

```
[2026-08-15 22:05:16] watcher started (pid 24196)
[2026-08-15 22:05:16] archon    : C:\Program Files\Archon App\Archon App.exe
[2026-08-15 22:05:16] watching  : ^Wow(Classic|T|B)?$  every 1s
[2026-08-15 22:05:16] delay     : 3s after the game is spotted
[2026-08-15 22:18:41] game detected
[2026-08-15 22:18:41] waiting 3s before launching
[2026-08-15 22:18:44] launched C:\Program Files\Archon App\Archon App.exe
[2026-08-15 23:47:02] game exited
```

If Archon was already open when you started the game you'll see
`Archon already running - nothing to do` instead, which is also correct.

**Nothing in the log after launching WoW** — the process name probably doesn't
match. Open Task Manager → Details while the game is running, note the exact
`.exe` name, and set `GamePattern` in `config.json` to match it (without the
`.exe`). Then run `Install.cmd` again.

**`FATAL: could not locate "Archon App.exe"`** — set `ArchonExe` in
`config.json` to the full path, then run `Install.cmd` again.

**Archon starts but stays behind the game** — that is Archon's own behaviour.
It opens its window *without* taking focus, so with the game in exclusive
fullscreen you won't see it until you alt-tab. Nothing to fix here; it did
start.

**`ViewLog.cmd` says the task state is `Ready`** — it only starts at logon.
Run `Install.cmd` again to start it now, or just sign out and back in.

## Notes

- Windows 10/11, PowerShell 5.1 (the built-in one). No modules required.
- Polling, not process-creation events. Event-driven detection needs
  administrator rights or an audit-policy change, and the measured cost of
  polling doesn't justify either.
- Nothing here modifies, patches, or injects into Archon or WoW. It only calls
  `Start-Process` on the Archon executable.

## License

Public domain / CC0. Do whatever you like with it.
