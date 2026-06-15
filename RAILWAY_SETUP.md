# Railway setup

This project deploys on Railway with the root `Dockerfile`.

## Required Railway variables

Open the Railway service, go to `Variables`, and add:

```text
TELEGRAM_BOT_TOKEN=your_telegram_bot_token
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5.4-mini
TRANSLATION_CONCURRENCY=10
QUEUE_MAXSIZE=0
DROP_PENDING_UPDATES=true
LOG_LEVEL=INFO
```

Do not upload `.env` to GitHub. Railway variables replace `.env` in the cloud.

## Important

Only one copy of a Telegram long-polling bot can run at a time. Stop the local
Windows bot before starting the Railway version.

## Redeploy

After changing variables or pushing a commit, redeploy the latest commit in
Railway.
