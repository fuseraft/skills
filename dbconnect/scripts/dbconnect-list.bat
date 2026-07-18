@echo off
setlocal
call "%~dp0dbconnect-run.bat" --list
exit /b %ERRORLEVEL%
