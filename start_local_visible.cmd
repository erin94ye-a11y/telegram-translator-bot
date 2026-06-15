@echo off
setlocal

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo Missing .venv Python. Please install dependencies first.
  pause
  exit /b 1
)

".venv\Scripts\python.exe" -u bot.py

echo.
echo Bot stopped. Press any key to close this window.
pause >nul
