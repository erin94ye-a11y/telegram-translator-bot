$ErrorActionPreference = "Stop"

$accountId = "504eb23138a764778d18667edcb80112"
$scriptName = "telegram-translator-bot"
$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot ".env"
$workerPath = Join-Path $PSScriptRoot "src\index.js"

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
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function Invoke-CloudflareApi($method, $path, $body = $null, $contentType = "application/json") {
    $uri = "https://api.cloudflare.com/client/v4$path"
    $headers = @{ Authorization = "Bearer $cloudflareToken" }

    if ($null -eq $body) {
        $result = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 90
    } else {
        $result = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType $contentType -Body $body -TimeoutSec 90
    }

    if (-not $result.success) {
        throw "Cloudflare API failed: $($result.errors | ConvertTo-Json -Depth 10)"
    }

    return $result
}

function New-StringContent($text, $contentType) {
    $content = [System.Net.Http.StringContent]::new($text, [System.Text.Encoding]::UTF8)
    $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($contentType)
    return $content
}

function Upload-WorkerScript {
    $metadata = @{
        main_module = "src/index.js"
        compatibility_date = "2026-06-12"
        workers_dev = $true
        bindings = @(
            @{
                name = "OPENAI_MODEL"
                type = "plain_text"
                text = "gpt-5.4-mini"
            },
            @{
                name = "TRANSLATION_CONCURRENCY"
                type = "plain_text"
                text = "10"
            },
            @{
                name = "TRANSLATION_QUEUE"
                type = "durable_object_namespace"
                class_name = "TranslationQueue"
            }
        )
        migrations = @(
            @{
                tag = "v1"
                new_sqlite_classes = @("TranslationQueue")
            }
        )
        annotations = @{
            "workers/message" = "Deploy Telegram translator bot"
            "workers/tag" = "telegram-translator"
        }
    } | ConvertTo-Json -Depth 20 -Compress

    $workerCode = Get-Content -LiteralPath $workerPath -Raw -Encoding UTF8

    $form = [System.Net.Http.MultipartFormDataContent]::new()
    $form.Add((New-StringContent $metadata "application/json"), "metadata")
    $form.Add((New-StringContent $workerCode "application/javascript+module"), "src/index.js", "src/index.js")

    $client = [System.Net.Http.HttpClient]::new()
    try {
        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $cloudflareToken)
        $uri = "https://api.cloudflare.com/client/v4/accounts/$accountId/workers/scripts/$scriptName"
        $response = $client.PutAsync($uri, $form).GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode) {
            throw "Upload Worker failed: HTTP $([int]$response.StatusCode) $responseText"
        }

        $result = $responseText | ConvertFrom-Json
        if (-not $result.success) {
            throw "Upload Worker failed: $($result.errors | ConvertTo-Json -Depth 10)"
        }
    }
    finally {
        $client.Dispose()
        $form.Dispose()
    }
}

function Put-WorkerSecret($name, $value) {
    $body = @{
        name = $name
        text = $value
        type = "secret_text"
    } | ConvertTo-Json -Compress

    Invoke-CloudflareApi "Put" "/accounts/$accountId/workers/scripts/$scriptName/secrets" $body | Out-Null
}

function Get-WorkersDevUrl {
    try {
        $result = Invoke-CloudflareApi "Get" "/accounts/$accountId/workers/subdomain"
        if ($result.result.subdomain) {
            return "https://$scriptName.$($result.result.subdomain).workers.dev"
        }
    } catch {
        Write-Host "Could not auto-detect workers.dev subdomain: $($_.Exception.Message)"
    }

    return Read-Host "Paste your Worker URL, for example https://$scriptName.YOUR_SUBDOMAIN.workers.dev"
}

Write-Host "Cloudflare direct API deployment starting..."
Write-Host "Worker: $scriptName"

$cloudflareToken = $env:CLOUDFLARE_API_TOKEN
if ([string]::IsNullOrWhiteSpace($cloudflareToken)) {
    $cloudflareToken = Read-Host "Cloudflare API Token"
}

$telegramToken = Read-DotEnvValue $envPath "TELEGRAM_BOT_TOKEN"
$openAiKey = Read-DotEnvValue $envPath "OPENAI_API_KEY"
$webhookSecret = $env:TELEGRAM_WEBHOOK_SECRET
if ([string]::IsNullOrWhiteSpace($webhookSecret)) {
    $webhookSecret = New-WebhookSecret
}

$cloudflareToken = Require-Value "CLOUDFLARE_API_TOKEN" $cloudflareToken
$telegramToken = Require-Value "TELEGRAM_BOT_TOKEN in .env" $telegramToken
$openAiKey = Require-Value "OPENAI_API_KEY in .env" $openAiKey

Write-Host "Verifying Cloudflare token..."
Invoke-CloudflareApi "Get" "/user/tokens/verify" | Out-Null

Write-Host "Uploading Worker script..."
Upload-WorkerScript

Write-Host "Uploading Worker secrets..."
Put-WorkerSecret "TELEGRAM_BOT_TOKEN" $telegramToken
Put-WorkerSecret "OPENAI_API_KEY" $openAiKey
Put-WorkerSecret "TELEGRAM_WEBHOOK_SECRET" $webhookSecret

Write-Host "Detecting Worker URL..."
$workerUrl = Get-WorkersDevUrl
$webhookUrl = "$workerUrl/telegram-webhook"

Write-Host "Setting Telegram webhook..."
$telegramResult = Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$telegramToken/setWebhook" -Body @{
    url = $webhookUrl
    secret_token = $webhookSecret
    drop_pending_updates = "false"
} -TimeoutSec 90

if (-not $telegramResult.ok) {
    throw "Telegram setWebhook failed: $($telegramResult | ConvertTo-Json -Depth 10)"
}

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Worker URL: $workerUrl"
Write-Host "Telegram webhook: $webhookUrl"
Write-Host "Send /start to the bot, then send Chinese text to test."
