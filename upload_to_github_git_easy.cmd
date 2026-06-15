@echo off
setlocal

cd /d "%~dp0"
echo This will upload the project to GitHub using Git push.
echo If the API uploader is stuck, use this one.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_to_github_git_easy.ps1"
pause
