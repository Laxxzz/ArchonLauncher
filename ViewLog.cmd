@echo off
setlocal
title Archon Launcher - Log

echo.
echo   Archon Launcher
echo   ---------------
echo.

rem Version is read out of the installed script so it always reflects what is
rem actually running, not what happens to be sitting in this folder.
rem
rem The pattern below deliberately avoids a negated class like [^']. cmd treats
rem ^ as its escape character and strips it even inside quotes, so [^'] arrives
rem at PowerShell as ['] -- an inverted match that silently finds nothing. The
rem non-greedy (.+?) needs no caret and behaves identically here.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Join-Path $env:LOCALAPPDATA 'ArchonLauncher\ArchonLauncher.ps1'; if(Test-Path $s){ $m = Select-String -Path $s -Pattern \"ArchonLauncherVersion\s*=\s*'(.+?)'\" | Select-Object -First 1; if($m){ Write-Host \"  Installed version : $($m.Matches[0].Groups[1].Value)\" } else { Write-Host '  Installed version : unknown (script present but no version marker)' } } else { Write-Host '  Installed version : NOT INSTALLED - run Install.cmd' }"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$w = Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*ArchonLauncher.ps1*' } | Select-Object -First 1; if($w){ Write-Host \"  Watcher           : RUNNING (pid $($w.ProcessId))\" } else { Write-Host '  Watcher           : NOT RUNNING - the heartbeat should start it within 5'; Write-Host '                      minutes, or run Install.cmd to start it now.' }; $t = Get-ScheduledTask -TaskName ArchonLauncher -ErrorAction SilentlyContinue; if($t){ Write-Host '  Scheduled task    : installed' } else { Write-Host '  Scheduled task    : NOT INSTALLED - run Install.cmd' }"

echo.
echo   Recent activity
echo   ---------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$l=Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'; if(Test-Path $l){ Get-Content $l -Tail 30 } else { Write-Host '  No log yet - is it installed? Run Install.cmd.' }"

echo.
echo   Press any key to close this window.
pause >nul
endlocal
