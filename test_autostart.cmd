@echo off
setlocal

cd /d "%~dp0"

echo Installing Windows login autostart entry...
call "%~dp0install_autostart.cmd"
if errorlevel 1 (
  echo.
  echo Failed to install autostart.
  pause
  exit /b 1
)

set "STARTUP_ENTRY=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\TelegramTranslatorBot.vbs"

if not exist "%STARTUP_ENTRY%" (
  echo.
  echo Autostart entry was not found:
  echo %STARTUP_ENTRY%
  pause
  exit /b 1
)

echo.
echo Installed autostart entry:
echo %STARTUP_ENTRY%

echo.
echo Starting the installed hidden autostart entry now...
wscript.exe "%STARTUP_ENTRY%"

echo Waiting for the bot to start...
timeout /t 10 /nobreak >nul

echo.
if exist "work\bot.pid" (
  set /p BOT_PID=<"work\bot.pid"
  echo Bot pid: %BOT_PID%
  tasklist /FI "PID eq %BOT_PID%"
) else (
  echo Bot pid file was not created.
)

echo.
echo Recent bot log:
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path 'work\bot.log') { Get-Content 'work\bot.log' -Tail 50 } else { Write-Host 'No bot.log found yet.' }"

echo.
echo If you see "Application started", the hidden autostart entry works.
echo You can now send /start to the Telegram bot.
echo.
pause
