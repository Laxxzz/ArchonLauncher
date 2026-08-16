@echo off
setlocal
title Archon Launcher - Install

echo.
echo   Archon Launcher
echo   Starts the Archon App when World of Warcraft launches.
echo   ------------------------------------------------------
echo.

rem Clear the "downloaded from the internet" mark so the scripts can run.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

rem Arguments passed on the command line win; otherwise ask.
set "OPTS=%*"
if not "%OPTS%"=="" goto run

choice /C YN /N /M "  Also close Archon when you quit WoW?  [Y/N] "
if errorlevel 2 goto run
set "OPTS=-QuitWithWow"

:run
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %OPTS%
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo   All set - launch WoW to test it.
) else (
  echo   Install failed with exit code %RC%.
  echo   Check the messages above, then see README.md.
)
echo.
echo   Press any key to close this window.
pause >nul
endlocal
