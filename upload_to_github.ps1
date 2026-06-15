$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "Preparing to upload this project to GitHub..."

function Fail($message) {
    Write-Host ""
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "Git was not found. Install Git for Windows first."
}

if (-not (Test-Path -LiteralPath ".git")) {
    git init
}

git check-ignore -q ".env"
if ($LASTEXITCODE -ne 0) {
    Fail ".env is not ignored. Refusing to upload secrets."
}

$secretPattern = "sk-[A-Za-z0-9_-]{20,}|cfat_[A-Za-z0-9_-]{20,}|cfut_[A-Za-z0-9_-]{20,}|[0-9]{8,}:[A-Za-z0-9_-]{30,}"
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

$repoUrl = Read-Host "GitHub repository URL, for example https://github.com/USER/REPO.git"
if ([string]::IsNullOrWhiteSpace($repoUrl)) {
    Fail "Repository URL is required."
}

$userName = git config user.name
if ([string]::IsNullOrWhiteSpace($userName)) {
    git config user.name "Codex User"
}

$userEmail = git config user.email
if ([string]::IsNullOrWhiteSpace($userEmail)) {
    git config user.email "codex-user@example.local"
}

Write-Host "Adding files..."
git add -A

$status = git status --short
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "No local changes to commit."
} else {
    Write-Host "Creating commit..."
    git commit -m "Initial Telegram translator bot"
}

git branch -M main

$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    git remote add origin $repoUrl
} else {
    git remote set-url origin $repoUrl
}

Write-Host "Pushing to GitHub..."
git push -u origin main

Write-Host ""
Write-Host "Upload complete."
