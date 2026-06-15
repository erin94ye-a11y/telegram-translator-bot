@echo off
setlocal

set "ROOT=%~dp0"
set "PID_FILE=%ROOT%work\bot.pid"

if not exist "%PID_FILE%" (
  echo Bot pid file was not found.
  exit /b 1
)

set /p PID=<"%PID_FILE%"
if "%PID%"=="" (
  echo Bot pid file is empty.
  exit /b 1
)

taskkill /PID %PID% /F
