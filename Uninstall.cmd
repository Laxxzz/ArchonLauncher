@echo off
setlocal
title Archon Launcher - Uninstall

echo.
echo   Archon Launcher - Uninstall
echo   ---------------------------
echo.
echo   This removes the scheduled task and stops the watcher.
echo   Your Archon App settings are not touched.
echo.

choice /C YN /N /M "  Remove Archon Launcher?  [Y/N] "
if errorlevel 2 goto cancelled

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo   Removed.
) else (
  echo   Uninstall failed with exit code %RC%.
)
goto done

:cancelled
echo.
echo   Cancelled - nothing was changed.

:done
echo.
echo   Press any key to close this window.
pause >nul
endlocal
