@echo off
setlocal

cd /d "%~dp0"
echo This will upload the project to GitHub using the GitHub API.
echo You only need to paste your Fine-grained Personal Access Token and enter a repository name.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_to_github_api.ps1"
pause
