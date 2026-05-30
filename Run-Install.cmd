@echo off
REM ===========================================================================
REM  Run-Install.cmd
REM  Double-click launcher for the FULL run (LOOK -> INSTALL -> CHECK).
REM  Self-elevates to Administrator and bypasses PowerShell execution policy
REM  for this one script only.
REM ===========================================================================
setlocal
set "PS1=%~dp0Install-Cisco.ps1"

if not exist "%PS1%" (
    echo ERROR: Install-Cisco.ps1 not found next to this launcher.
    echo Expected: "%PS1%"
    pause
    exit /b 1
)

REM --- check for admin; if not, relaunch this .cmd elevated ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running Cisco migration installer as administrator...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%errorlevel%"
echo.
echo Exit code: %RC%   (0 = all pass, 1 = stopped before/at install, 2 = installed but verify warning)
echo.
pause
exit /b %RC%
