$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "Uploading project to GitHub using Git push..."

function Fail($message) {
    Write-Host ""
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

function Get-PlainTokenFromSecureString($secureString) {
    $credential = New-Object System.Management.Automation.PSCredential("token", $secureString)
    return $credential.GetNetworkCredential().Password
}

function Invoke-GitHubApi($method, $path, $body = $null) {
    $headers = @{
        Authorization = "Bearer $githubToken"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "telegram-translator-upload"
    }
    $uri = "https://api.github.com$path"

    if ($null -eq $body) {
        return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 45
    }

    $json = $body | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec 45
}

function UrlEncode($value) {
    return [System.Uri]::EscapeDataString($value)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "Git was not found. Install Git for Windows first."
}

$githubToken = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($githubToken)) {
    $secureToken = Read-Host "GitHub Fine-grained Personal Access Token" -AsSecureString
    $githubToken = Get-PlainTokenFromSecureString $secureToken
}

if ([string]::IsNullOrWhiteSpace($githubToken)) {
    Fail "GitHub token is required."
}

$githubUser = Read-Host "GitHub username [erin94ye-a11y]"
if ([string]::IsNullOrWhiteSpace($githubUser)) {
    $githubUser = "erin94ye-a11y"
}

$repoName = Read-Host "Repository name [telegram-translator-bot]"
if ([string]::IsNullOrWhiteSpace($repoName)) {
    $repoName = "telegram-translator-bot"
}

$cleanRemote = "https://github.com/$githubUser/$repoName.git"
$encodedUser = UrlEncode $githubUser
$encodedToken = UrlEncode $githubToken
$pushRemote = "https://${encodedUser}:${encodedToken}@github.com/$githubUser/$repoName.git"

Write-Host "Repository: $githubUser/$repoName"
Write-Host "Checking GitHub token repository access..."
try {
    $repoInfo = Invoke-GitHubApi "Get" "/repos/$githubUser/$repoName"
    if (-not $repoInfo.permissions.push) {
        Fail "This token can see the repository, but it does not have write/push permission. In the Fine-grained token settings, set Repository permissions -> Contents -> Read and write for this repository."
    }
} catch {
    Fail "Could not verify repository write access. Make sure the token is selected for $githubUser/$repoName and has Contents: Read and write."
}

Write-Host "Marking this folder as safe for Git..."
$safePath = $root.Replace("\", "/")
git config --global --add safe.directory $safePath

if (-not (Test-Path -LiteralPath ".git")) {
    git init
}

Write-Host "Checking that secrets are ignored..."
git check-ignore -q ".env"
if ($LASTEXITCODE -ne 0) {
    Fail ".env is not ignored. Refusing to upload secrets."
}

$secretPattern = "sk-[A-Za-z0-9_-]{20,}|cfat_[A-Za-z0-9_-]{20,}|cfut_[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|[0-9]{8,}:[A-Za-z0-9_-]{30,}"
$candidateFiles = git ls-files --cached --others --exclude-standard
$matches = @()
foreach ($file in $candidateFiles) {
    if ((Test-Path -LiteralPath $file -PathType Leaf) -and ((Split-Path -Leaf $file) -ne ".env")) {
        $matches += Select-String -LiteralPath $file -Pattern $secretPattern -ErrorAction SilentlyContinue
    }
}

if ($matches) {
    Write-Host "Potential secrets found in files:" -ForegroundColor Yellow
    $matches | Select-Object -ExpandProperty Path -Unique | ForEach-Object { Write-Host $_ }
    Fail "Remove these secrets before uploading."
}

Write-Host "Adding project files..."
git add -A

$status = git status --short
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "No local file changes to commit."
} else {
    Write-Host "Creating commit..."
    git config user.name "Codex User"
    git config user.email "codex-user@example.local"
    git commit -m "Initial Telegram translator bot"
}

git branch -M main

try {
    $remoteNames = @(git remote)
    if ($remoteNames -notcontains "origin") {
        git remote add origin $pushRemote
    } else {
        git remote set-url origin $pushRemote
    }

    Write-Host "Pushing to GitHub..."
    git -c credential.helper= -c core.askpass= push -u origin main
    $pushExitCode = $LASTEXITCODE
    if ($pushExitCode -ne 0) {
        Fail "Git push failed. This almost always means the token does not have Contents: Read and write permission for $githubUser/$repoName, or the repository owner/name is not correct."
    }
}
finally {
    $remoteNames = @(git remote)
    if ($remoteNames -contains "origin") {
        git remote set-url origin $cleanRemote
    }
}

Write-Host ""
Write-Host "Upload complete:"
Write-Host $cleanRemote.Replace(".git", "")
