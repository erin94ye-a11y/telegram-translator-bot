@echo off
setlocal

cd /d "%~dp0"

call "%~dp0stop_bot.cmd"
echo Starting bot in hidden mode...
wscript.exe "%~dp0start_bot_hidden.vbs"

echo Waiting for the bot to start...
timeout /t 8 /nobreak >nul

echo.
if exist "work\bot.log" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content 'work\bot.log' -Tail 30"
) else (
  echo No bot log found yet.
)

echo.
echo Done. Send Chinese text or a chat screenshot to the Telegram bot to test the Elena Vega translation style.
pause
