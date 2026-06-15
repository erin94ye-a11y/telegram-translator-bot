@echo off
setlocal

set "STARTUP_ENTRY=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\TelegramTranslatorBot.vbs"

if exist "%STARTUP_ENTRY%" (
  del "%STARTUP_ENTRY%"
  echo Removed autostart entry:
  echo %STARTUP_ENTRY%
) else (
  echo Autostart entry was not found.
)

pause
