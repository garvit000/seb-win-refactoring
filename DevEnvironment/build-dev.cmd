@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-dev.ps1" %*
exit /b %ERRORLEVEL%
