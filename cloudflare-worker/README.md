# Telegram Translator Cloudflare Worker

This Worker receives Telegram updates by webhook, enqueues Chinese messages in a
Durable Object, and processes up to 10 translation jobs at a time with OpenAI.

Required Cloudflare token permissions:

- Account: Workers Scripts: Edit
- Account: Workers Durable Objects: Edit, if shown in your token UI
- Account: Account Settings: Read

Required Worker secrets:

- `TELEGRAM_BOT_TOKEN`
- `OPENAI_API_KEY`
- `TELEGRAM_WEBHOOK_SECRET`

Deploy:

PowerShell, no npm required:

```powershell
cd "C:\Users\User\Documents\翻译机器人\cloudflare-worker"
$env:CLOUDFLARE_API_TOKEN="your_cloudflare_api_token"
.\deploy_direct.cmd
```

Wrangler-based deploy, if Node.js/npm is installed:

```powershell
$env:CLOUDFLARE_API_TOKEN="your_cloudflare_api_token"
.\deploy.ps1
```

Linux/macOS:

```bash
export CLOUDFLARE_API_TOKEN="your_cloudflare_api_token"
bash ./deploy.sh
```

Manual webhook setup, if needed:

```bash
curl "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://YOUR_WORKER_URL/telegram-webhook" \
  -d "secret_token=$TELEGRAM_WEBHOOK_SECRET"
```
