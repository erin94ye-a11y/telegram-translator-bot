@echo off
setlocal

set "ROOT=%~dp0"
set "PYTHON=%ROOT%.venv\Scripts\python.exe"
set "BOT=%ROOT%bot.py"
set "WORK=%ROOT%work"

if not exist "%WORK%" mkdir "%WORK%"

"%PYTHON%" -u "%BOT%" 1>>"%WORK%\bot.out.log" 2>>"%WORK%\bot.err.log"
