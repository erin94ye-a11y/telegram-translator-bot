#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

dotenv_get() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  grep -E "^[[:space:]]*$key[[:space:]]*=" "$ENV_FILE" | head -n 1 | sed -E "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//"
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required value: $name" >&2
    exit 1
  fi
}

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  read -rsp "Cloudflare API Token: " CLOUDFLARE_API_TOKEN
  echo
  export CLOUDFLARE_API_TOKEN
fi

TELEGRAM_BOT_TOKEN="$(dotenv_get TELEGRAM_BOT_TOKEN || true)"
OPENAI_API_KEY="$(dotenv_get OPENAI_API_KEY || true)"
TELEGRAM_WEBHOOK_SECRET="${TELEGRAM_WEBHOOK_SECRET:-$(openssl rand -hex 32)}"

require_value "CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_API_TOKEN"
require_value "TELEGRAM_BOT_TOKEN in .env" "$TELEGRAM_BOT_TOKEN"
require_value "OPENAI_API_KEY in .env" "$OPENAI_API_KEY"

cd "$SCRIPT_DIR"
npm install

DEPLOY_OUTPUT="$(npx wrangler deploy 2>&1 | tee /dev/stderr)"
WORKER_URL="$(printf '%s\n' "$DEPLOY_OUTPUT" | grep -Eo 'https://[^[:space:]]+\.workers\.dev' | head -n 1)"

if [[ -z "$WORKER_URL" ]]; then
  echo "Could not detect the workers.dev URL from Wrangler output." >&2
  exit 1
fi

printf '%s' "$TELEGRAM_BOT_TOKEN" | npx wrangler secret put TELEGRAM_BOT_TOKEN
printf '%s' "$OPENAI_API_KEY" | npx wrangler secret put OPENAI_API_KEY
printf '%s' "$TELEGRAM_WEBHOOK_SECRET" | npx wrangler secret put TELEGRAM_WEBHOOK_SECRET

WEBHOOK_URL="$WORKER_URL/telegram-webhook"
curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=$WEBHOOK_URL" \
  -d "secret_token=$TELEGRAM_WEBHOOK_SECRET" \
  -d "drop_pending_updates=false" >/dev/null

echo "Cloudflare Worker deployed: $WORKER_URL"
echo "Telegram webhook set: $WEBHOOK_URL"
echo "Send /start to the bot, then send Chinese text to test translation."
