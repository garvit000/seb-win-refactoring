@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-last-run.ps1" %*
exit /b %ERRORLEVEL%
