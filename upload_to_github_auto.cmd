@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo This will upload the current project folder to GitHub.
echo It will NOT upload .env, logs, virtual environments, or local cache folders.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_to_github_auto.ps1"
echo.
pause
