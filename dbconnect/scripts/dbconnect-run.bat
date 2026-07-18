@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%dbconnect-run.ps1" %*
exit /b %ERRORLEVEL%
