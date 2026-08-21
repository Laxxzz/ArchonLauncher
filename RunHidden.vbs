' RunHidden.vbs -- starts the watcher with no console window at all.
'
' Running powershell.exe directly from Task Scheduler creates a console window
' every time the task fires. "-WindowStyle Hidden" does not prevent it: that
' switch applies to the PowerShell host window after startup, while the console
' itself is allocated before the script runs, so it flashes on screen. The task's
' own "Hidden" setting is unrelated -- it hides the task in the Task Scheduler
' library, not the window.
'
' WScript.Shell.Run with window style 0 launches the process with no window from
' the outset. wscript.exe exits immediately, so the watcher outlives it and the
' scheduled task shows as finished; duplicate starts are prevented by the mutex
' inside ArchonLauncher.ps1 rather than by the task's MultipleInstances policy.
'
' Any arguments given here are passed through to the script.

Option Explicit

Dim shell, fso, scriptDir, target, args, i, cmd

Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
target    = fso.BuildPath(scriptDir, "ArchonLauncher.ps1")

If Not fso.FileExists(target) Then
    ' Nothing sensible to do, and no console to complain to.
    WScript.Quit 1
End If

args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ _
      & target & """" & args

' 0 = hidden window, False = do not wait for it to finish.
shell.Run cmd, 0, False
