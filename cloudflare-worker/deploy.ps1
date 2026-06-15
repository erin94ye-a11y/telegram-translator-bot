$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot ".env"

Write-Host "Starting Cloudflare Worker deployment..."
Write-Host "Project: $PSScriptRoot"

function Read-DotEnvValue($path, $key) {
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $line = Get-Content -LiteralPath $path | Where-Object {
        $_ -match "^\s*$([regex]::Escape($key))\s*="
    } | Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -replace "^\s*$([regex]::Escape($key))\s*=\s*", "").Trim()
}

function Require-Value($name, $value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required value: $name"
    }
    return $value
}

function New-WebhookSecret {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToHexString($bytes).ToLowerInvariant()
}

$cloudflareToken = $env:CLOUDFLARE_API_TOKEN
if ([string]::IsNullOrWhiteSpace($cloudflareToken)) {
    Write-Host "CLOUDFLARE_API_TOKEN was not found in this PowerShell session."
    $cloudflareToken = Read-Host "Cloudflare API Token"
}

Write-Host "Reading Telegram and OpenAI secrets from: $envPath"
$telegramToken = Read-DotEnvValue $envPath "TELEGRAM_BOT_TOKEN"
$openAiKey = Read-DotEnvValue $envPath "OPENAI_API_KEY"
$webhookSecret = $env:TELEGRAM_WEBHOOK_SECRET
if ([string]::IsNullOrWhiteSpace($webhookSecret)) {
    Write-Host "Generating Telegram webhook secret..."
    $webhookSecret = New-WebhookSecret
}

$cloudflareToken = Require-Value "CLOUDFLARE_API_TOKEN" $cloudflareToken
$telegramToken = Require-Value "TELEGRAM_BOT_TOKEN in .env" $telegramToken
$openAiKey = Require-Value "OPENAI_API_KEY in .env" $openAiKey

$npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npm) {
    throw "npm was not found. Install Node.js 20+ first, then run this script again."
}

Write-Host "npm found: $($npm.Source)"

Push-Location $PSScriptRoot
try {
    $env:CLOUDFLARE_API_TOKEN = $cloudflareToken

    Write-Host "Installing Wrangler dependency with npm..."
    npm install

    Write-Host "Deploying Worker to Cloudflare..."
    $deployOutput = npx wrangler deploy 2>&1 | Tee-Object -Variable deployLines
    $workerUrl = ($deployLines | Select-String -Pattern "https://[^\s]+\.workers\.dev" | Select-Object -First 1).Matches.Value
    if ([string]::IsNullOrWhiteSpace($workerUrl)) {
        throw "Could not detect the workers.dev URL from Wrangler output."
    }

    Write-Host "Uploading Worker secrets..."
    $telegramToken | npx wrangler secret put TELEGRAM_BOT_TOKEN
    $openAiKey | npx wrangler secret put OPENAI_API_KEY
    $webhookSecret | npx wrangler secret put TELEGRAM_WEBHOOK_SECRET

    Write-Host "Setting Telegram webhook..."
    $webhookUrl = "$workerUrl/telegram-webhook"
    $setWebhookUri = "https://api.telegram.org/bot$telegramToken/setWebhook"
    $result = Invoke-RestMethod -Method Post -Uri $setWebhookUri -Body @{
        url = $webhookUrl
        secret_token = $webhookSecret
        drop_pending_updates = "false"
    }

    if (-not $result.ok) {
        throw "Telegram setWebhook failed: $($result | ConvertTo-Json -Depth 5)"
    }

    Write-Host "Cloudflare Worker deployed: $workerUrl"
    Write-Host "Telegram webhook set: $webhookUrl"
    Write-Host "Send /start to the bot, then send Chinese text to test translation."
}
finally {
    Pop-Location
}
