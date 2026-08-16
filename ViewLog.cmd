@echo off
setlocal
title Archon Launcher - Log

echo.
echo   Archon Launcher - recent activity
echo   ---------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$l=Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'; if(Test-Path $l){ Get-Content $l -Tail 30 } else { Write-Host '  No log yet - is it installed? Run Install.cmd.' }"

echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=Get-ScheduledTask -TaskName ArchonLauncher -ErrorAction SilentlyContinue; if($t){ Write-Host \"  Task state: $($t.State)\" } else { Write-Host '  Scheduled task not installed.' }"

echo.
echo   Press any key to close this window.
pause >nul
endlocal
