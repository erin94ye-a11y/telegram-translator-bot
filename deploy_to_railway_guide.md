# Railway local deployment

This project can be deployed directly from the local folder with Railway CLI.
No GitHub repository is required.

## One-time setup

Install Node.js 20+ from:

https://nodejs.org/

Then install Railway CLI:

```powershell
npm install -g @railway/cli
```

Log in:

```powershell
railway login
```

## Deploy this bot

The easiest way on Windows is to double-click:

```text
deploy_to_railway.cmd
```

The first run may install Railway CLI and can take a few minutes. Keep the window
open. A log is written to:

```text
work\railway_deploy.log
```

Manual PowerShell commands, if needed:

```powershell
cd "C:\Users\User\Documents\翻译机器人"
railway link
railway variables --set "TELEGRAM_BOT_TOKEN=your_telegram_bot_token"
railway variables --set "OPENAI_API_KEY=your_openai_api_key"
railway variables --set "OPENAI_MODEL=gpt-5.4-mini"
railway variables --set "TRANSLATION_CONCURRENCY=10"
railway variables --set "QUEUE_MAXSIZE=0"
railway variables --set "DROP_PENDING_UPDATES=false"
railway variables --set "LOG_LEVEL=INFO"
railway up
```

After deployment, open Railway Logs. If you see `Application started`, the bot is running.
