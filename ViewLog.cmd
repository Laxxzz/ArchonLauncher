@echo off
setlocal
title Archon Launcher - Log

echo.
echo   Archon Launcher - recent activity
echo   ---------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$l=Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'; if(Test-Path $l){ Get-Content $l -Tail 30 } else { Write-Host '  No log yet - is it installed? Run Install.cmd.' }"

echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$w = Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*ArchonLauncher.ps1*' } | Select-Object -First 1; if($w){ Write-Host \"  Watcher: RUNNING (pid $($w.ProcessId))\" } else { Write-Host '  Watcher: NOT RUNNING - the heartbeat should start it within 5 minutes,'; Write-Host '           or run Install.cmd to start it now.' }; $t = Get-ScheduledTask -TaskName ArchonLauncher -ErrorAction SilentlyContinue; if($t){ Write-Host '  Task   : installed' } else { Write-Host '  Task   : NOT INSTALLED - run Install.cmd' }"

echo.
echo   Press any key to close this window.
pause >nul
endlocal
