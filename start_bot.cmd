@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%.venv\Scripts\python.exe"
set "BOT=%ROOT%bot.py"

if not exist "%PYTHON%" (
  echo Missing .venv. Install dependencies first.
  exit /b 1
)

"%PYTHON%" "%BOT%"
