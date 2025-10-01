@echo off
setlocal
REM PowerShell 5 (Windows)
set PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
"%PS%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0topic_breakdown_bare_repo.ps1"
echo.
echo -------- Press any key to close --------
pause >nul
