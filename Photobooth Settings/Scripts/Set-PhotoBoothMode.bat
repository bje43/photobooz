@echo off
REM Set-PhotoBoothMode.bat
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Set-PhotoBoothMode.ps1"

REM Launch the GUI picker. You can also pass a mode:  Set-PhotoBoothMode.bat Normal
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Mode "%~1"
)

endlocal
exit /b %ERRORLEVEL%
