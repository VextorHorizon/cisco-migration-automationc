@echo off
REM ===========================================================================
REM  Run-Preflight.cmd
REM  Double-click launcher for the SAFE TEST (LOOK only - read-only).
REM  Installs NOTHING. Use this first on any machine to confirm the script
REM  finds every required file before you ever run a real install.
REM ===========================================================================
setlocal
set "PS1=%~dp0Install-Cisco.ps1"

if not exist "%PS1%" (
    echo ERROR: Install-Cisco.ps1 not found next to this launcher.
    echo Expected: "%PS1%"
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running LOOK phase only (read-only, installs nothing)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -PreflightOnly
set "RC=%errorlevel%"
echo.
echo Exit code: %RC%   (0 = GREEN safe to install, 1 = RED something missing)
echo.
pause
exit /b %RC%
