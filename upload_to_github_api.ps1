$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "Uploading project to GitHub through the REST API..."

function Fail($message) {
    Write-Host ""
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

function Get-PlainTokenFromSecureString($secureString) {
    $credential = New-Object System.Management.Automation.PSCredential("token", $secureString)
    return $credential.GetNetworkCredential().Password
}

function Parse-GitHubRepo($value) {
    $text = $value.Trim()
    $text = $text -replace "\.git$", ""

    if ($text -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+)$") {
        return @{ owner = $Matches.owner; repo = $Matches.repo }
    }

    if ($text -match "^(?<owner>[^/]+)/(?<repo>[^/]+)$") {
        return @{ owner = $Matches.owner; repo = $Matches.repo }
    }

    if ($text -match "^[A-Za-z0-9_.-]+$") {
        return @{ owner = $null; repo = $text }
    }

    Fail "Could not parse GitHub repository. Use a simple repo name, owner/repo, or https://github.com/owner/repo.git"
}

function Invoke-GitHubApi($method, $path, $body = $null, $allowNotFound = $false) {
    $headers = @{
        Authorization = "Bearer $githubToken"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "telegram-translator-upload"
    }
    $uri = "https://api.github.com$path"

    try {
        if ($null -eq $body) {
            return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 45
        }

        $json = $body | ConvertTo-Json -Depth 100
        return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec 45
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($allowNotFound -and ($statusCode -eq 404 -or $statusCode -eq 409)) {
            return $null
        }

        if ($_.ErrorDetails.Message) {
            Fail "GitHub API request failed: $($_.ErrorDetails.Message)"
        }

        Fail "GitHub API request failed: $($_.Exception.Message)"
    }
}

function Get-UploadFiles {
    $excludedDirs = @(".git", ".venv", "work", "__pycache__", "node_modules", ".wrangler")
    $excludedFiles = @(".env", "package-lock.json")
    $files = @()

    foreach ($item in Get-ChildItem -Recurse -File -Force) {
        $relative = Resolve-Path -LiteralPath $item.FullName -Relative
        $normalized = $relative
        if ($normalized.StartsWith(".\") -or $normalized.StartsWith("./")) {
            $normalized = $normalized.Substring(2)
        }
        $normalized = $normalized.Replace("\", "/")
        $segments = $normalized -split "/"

        if ($segments | Where-Object { $excludedDirs -contains $_ }) {
            continue
        }

        if ($excludedFiles -contains $item.Name) {
            continue
        }

        if ($item.Name -like "*.log" -or $item.Name -like "*.pyc" -or $item.Name -like "*.pyo" -or $item.Name -like "*.pyd") {
            continue
        }

        if ($item.Name -like ".dev.vars*") {
            continue
        }

        $files += $relative
    }

    return $files
}

function Assert-NoSecrets($files) {
    $secretPattern = "sk-[A-Za-z0-9_-]{20,}|cfat_[A-Za-z0-9_-]{20,}|cfut_[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|[0-9]{8,}:[A-Za-z0-9_-]{30,}"
    $matches = @()

    foreach ($file in $files) {
        if ((Test-Path -LiteralPath $file -PathType Leaf) -and ((Split-Path -Leaf $file) -ne ".env")) {
            $matches += Select-String -LiteralPath $file -Pattern $secretPattern -ErrorAction SilentlyContinue
        }
    }

    if ($matches) {
        Write-Host "Potential secrets found in files:" -ForegroundColor Yellow
        $matches | Select-Object -ExpandProperty Path -Unique | ForEach-Object { Write-Host $_ }
        Fail "Remove these secrets before uploading."
    }
}

function New-GitHubBlob($owner, $repoName, $file) {
    $content = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    return Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/blobs" @{
        content = $content
        encoding = "utf-8"
    }
}

function Ensure-GitHubRepository($owner, $repoName) {
    Write-Host "Checking repository $owner/$repoName..."
    $existingRepo = Invoke-GitHubApi "Get" "/repos/$owner/$repoName" $null $true
    if ($existingRepo) {
        return $existingRepo
    }

    Write-Host "Repository was not found. I will try to create it as a private repository..."
    try {
        return Invoke-GitHubApi "Post" "/user/repos" @{
            name = $repoName
            private = $true
            auto_init = $true
            description = "Telegram bot for Chinese to American English translation"
        }
    } catch {
        Fail "Could not create the repository automatically. In GitHub, create an empty repository named '$repoName', then run this uploader again. Your token also needs repository Contents: Read and write."
    }
}

$githubToken = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($githubToken)) {
    $secureToken = Read-Host "GitHub Fine-grained Personal Access Token" -AsSecureString
    $githubToken = Get-PlainTokenFromSecureString $secureToken
}

if ([string]::IsNullOrWhiteSpace($githubToken)) {
    Fail "GITHUB_TOKEN is required."
}

Write-Host "Checking GitHub token..."
$currentUser = Invoke-GitHubApi "Get" "/user"
Write-Host "GitHub user: $($currentUser.login)"

$repoInput = Read-Host "Repository name [telegram-translator-bot]"
if ([string]::IsNullOrWhiteSpace($repoInput)) {
    $repoInput = "telegram-translator-bot"
}

$parsed = Parse-GitHubRepo $repoInput
$owner = if ([string]::IsNullOrWhiteSpace($parsed.owner)) { $currentUser.login } else { $parsed.owner }
$repoName = $parsed.repo

$repo = Ensure-GitHubRepository $owner $repoName

$branch = $repo.default_branch
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "main"
}

$files = Get-UploadFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if ($files.Count -eq 0) {
    Fail "No files to upload."
}

Write-Host "Checking files for accidental secrets..."
Assert-NoSecrets $files

Write-Host "Uploading $($files.Count) files to GitHub..."
$treeEntries = @()
$fileIndex = 0
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        continue
    }

    $path = $file
    if ($path.StartsWith(".\") -or $path.StartsWith("./")) {
        $path = $path.Substring(2)
    }
    $path = $path.Replace("\", "/")
    $mode = "100644"
    if ($path -like "*.sh") {
        $mode = "100755"
    }

    $fileIndex += 1
    Write-Host ("Uploading file {0}/{1}: {2}" -f $fileIndex, $files.Count, $path)
    $blob = New-GitHubBlob $owner $repoName $file

    $treeEntries += @{
        path = $path
        mode = $mode
        type = "blob"
        sha = $blob.sha
    }
}

$baseRef = Invoke-GitHubApi "Get" "/repos/$owner/$repoName/git/ref/heads/$branch" $null $true
if (-not $baseRef) {
    Write-Host "Repository is empty. I will create the first commit and main branch directly..."
}

$parents = @()
$baseTree = $null

if ($baseRef) {
    $baseSha = $baseRef.object.sha
    $baseCommit = Invoke-GitHubApi "Get" "/repos/$owner/$repoName/git/commits/$baseSha"
    $baseTree = $baseCommit.tree.sha
    $parents = @($baseSha)
}

$treeBody = @{ tree = $treeEntries }
if ($baseTree) {
    $treeBody.base_tree = $baseTree
}

Write-Host "Creating Git tree from uploaded files..."
$newTree = Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/trees" $treeBody

$commitMessage = Read-Host "Commit message [Initial Telegram translator bot]"
if ([string]::IsNullOrWhiteSpace($commitMessage)) {
    $commitMessage = "Initial Telegram translator bot"
}

$commitBody = @{
    message = $commitMessage
    tree = $newTree.sha
}
if ($parents.Count -gt 0) {
    $commitBody.parents = $parents
}

Write-Host "Creating commit..."
$newCommit = Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/commits" $commitBody

if ($baseRef) {
    Write-Host "Updating branch $branch..."
    Invoke-GitHubApi "Patch" "/repos/$owner/$repoName/git/refs/heads/$branch" @{
        sha = $newCommit.sha
        force = $false
    } | Out-Null
} else {
    Write-Host "Creating branch $branch..."
    Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/refs" @{
        ref = "refs/heads/$branch"
        sha = $newCommit.sha
    } | Out-Null
}

Write-Host ""
Write-Host "Upload complete:"
Write-Host "https://github.com/$owner/$repoName"
