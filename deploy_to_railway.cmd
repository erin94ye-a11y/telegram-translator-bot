@echo off
setlocal

cd /d "%~dp0"
set "LOG=%~dp0work\railway_deploy.log"
if not exist "%~dp0work" mkdir "%~dp0work"

call :main > "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"
type "%LOG%"
echo.
echo Log saved to:
echo %LOG%
echo.
pause
exit /b %RESULT%

:main
echo This deploys the current local folder directly to Railway.
echo No GitHub upload is required.
echo.

set "NPM=npm"
set "NPX=npx"
set "RAILWAY=railway"

if exist "C:\Program Files\nodejs\npm.cmd" set "NPM=C:\Program Files\nodejs\npm.cmd"
if exist "C:\Program Files\nodejs\npx.cmd" set "NPX=C:\Program Files\nodejs\npx.cmd"
if exist "%APPDATA%\npm\railway.cmd" set "RAILWAY=%APPDATA%\npm\railway.cmd"
if exist "%~dp0node_modules\.bin\railway.cmd" set "RAILWAY=%~dp0node_modules\.bin\railway.cmd"

where railway >nul 2>nul
if errorlevel 1 (
  if not exist "%RAILWAY%" (
    echo Railway CLI was not found.
  ) else (
    goto railway_found
  )
  echo.
  if not exist "%NPM%" (
    echo Node.js/npm was not found.
    echo Install Node.js first from:
    echo https://nodejs.org/
    echo.
    echo Then run this file again.
    pause
    exit /b 1
  )

  echo Installing Railway CLI locally with npm...
  echo This can take a few minutes. Please keep this window open.
  "%NPM%" install @railway/cli
  if errorlevel 1 (
    echo.
    echo Failed to install Railway CLI.
    exit /b 1
  )

  if exist "%~dp0node_modules\.bin\railway.cmd" set "RAILWAY=%~dp0node_modules\.bin\railway.cmd"
  if exist "%APPDATA%\npm\railway.cmd" set "RAILWAY=%APPDATA%\npm\railway.cmd"
)

:railway_found
where railway >nul 2>nul
if not errorlevel 1 (
  set "RAILWAY=railway"
)

if not exist "%RAILWAY%" if /i not "%RAILWAY%"=="railway" (
  echo Railway CLI still was not found after installation.
  exit /b 1
)

echo Checking Railway login...
"%RAILWAY%" whoami >nul 2>nul
if errorlevel 1 (
  echo You need to log in to Railway.
  "%RAILWAY%" login
  if errorlevel 1 (
    echo.
    echo Railway login failed.
    exit /b 1
  )
)

echo Linking this folder to your Railway project...
"%RAILWAY%" link
if errorlevel 1 (
  echo.
  echo Railway link failed. Make sure you are logged in with: railway login
  exit /b 1
)

echo.
echo Uploading environment variables from .env...
set "RAILWAY_EXE=%RAILWAY%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$railway = $env:RAILWAY_EXE;" ^
  "$vars = @('TELEGRAM_BOT_TOKEN','OPENAI_API_KEY','OPENAI_MODEL','TRANSLATION_CONCURRENCY','QUEUE_MAXSIZE','DROP_PENDING_UPDATES','LOG_LEVEL');" ^
  "$lines = Get-Content '.env';" ^
  "foreach ($name in $vars) {" ^
  "  $line = $lines | Where-Object { $_ -match ('^\s*' + [regex]::Escape($name) + '\s*=') } | Select-Object -First 1;" ^
  "  if ($line) {" ^
  "    $value = ($line -replace ('^\s*' + [regex]::Escape($name) + '\s*=\s*'), '').Trim();" ^
  "    if ($value) { & $railway variables --set (""$name=$value"") }" ^
  "  }" ^
  "}"
if errorlevel 1 (
  echo.
  echo Failed to upload one or more Railway variables.
  exit /b 1
)

echo.
echo Deploying to Railway...
"%RAILWAY%" up
if errorlevel 1 (
  echo.
  echo Railway deployment failed.
  exit /b 1
)

echo.
echo Deployment finished. Open Railway logs and look for: Application started
exit /b 0
