@echo off
setlocal

cd /d "%~dp0"

if not exist "work\bot.log" (
  echo No bot log found yet.
  pause
  exit /b 1
)

type "work\bot.log"
echo.
pause
