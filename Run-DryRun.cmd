@echo off
REM ===========================================================================
REM  Run-DryRun.cmd
REM  Double-click launcher for the PREVIEW (LOOK + show every install action).
REM  Executes NOTHING - it only prints what it WOULD do. Read-only, safe on a
REM  real client. No admin needed.
REM ===========================================================================
setlocal
set "PS1=%~dp0Install-Cisco.ps1"

if not exist "%PS1%" (
    echo ERROR: Install-Cisco.ps1 not found next to this launcher.
    echo Expected: "%PS1%"
    pause
    exit /b 1
)

echo Previewing install (DRY RUN - nothing will be executed)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -DryRun
set "RC=%errorlevel%"
echo.
echo Exit code: %RC%   (0 = preview shown, 1 = missing files, nothing to preview)
echo.
pause
exit /b %RC%
