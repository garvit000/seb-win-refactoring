@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0register-url-handler.ps1" %*
exit /b %ERRORLEVEL%
