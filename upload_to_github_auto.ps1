$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host ""
Write-Host "GitHub automatic uploader"
Write-Host "This uploader does not use saved Git credentials."
Write-Host "It uploads this folder directly through the GitHub API."
Write-Host ""

function Fail($message) {
    Write-Host ""
    Write-Host "ERROR: $message" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Get-PlainTokenFromSecureString($secureString) {
    $credential = New-Object System.Management.Automation.PSCredential("token", $secureString)
    return $credential.GetNetworkCredential().Password
}

function ConvertTo-Base64Url($text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return [Convert]::ToBase64String($bytes)
}

function Invoke-GitHubApi($method, $path, $body = $null, $allowMissing = $false) {
    $headers = @{
        Authorization = "Bearer $script:githubToken"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "telegram-translator-github-uploader"
    }

    $uri = "https://api.github.com$path"

    try {
        if ($null -eq $body) {
            return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -TimeoutSec 90
        }

        $json = $body | ConvertTo-Json -Depth 100 -Compress
        return Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec 90
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($allowMissing -and ($statusCode -eq 404 -or $statusCode -eq 409)) {
            return $null
        }

        $details = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = $_.Exception.Message
        }

        if ($details -match "Resource not accessible by personal access token" -or $statusCode -eq 403) {
            Fail "GitHub refused this token. Open the Fine-grained token settings and make sure this repository is selected, then set Repository permissions -> Contents -> Read and write."
        }

        if ($details -match "Bad credentials" -or $statusCode -eq 401) {
            Fail "GitHub says this token is invalid or expired. Create a new Fine-grained Personal Access Token and run this file again."
        }

        Fail "GitHub API request failed: $details"
    }
}

function Parse-RepositoryInput($value, $defaultOwner) {
    $text = $value.Trim()
    $text = $text -replace "\.git$", ""

    if ($text -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+)$") {
        return @{ owner = $Matches.owner; repo = $Matches.repo }
    }

    if ($text -match "^(?<owner>[^/]+)/(?<repo>[^/]+)$") {
        return @{ owner = $Matches.owner; repo = $Matches.repo }
    }

    if ($text -match "^[A-Za-z0-9_.-]+$") {
        return @{ owner = $defaultOwner; repo = $text }
    }

    Fail "Repository format was not recognized. Use repo-name, owner/repo, or https://github.com/owner/repo"
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

        if ($item.Length -gt 100MB) {
            Fail "File is larger than GitHub's normal upload limit: $normalized"
        }

        $files += [PSCustomObject]@{
            LocalPath = $relative
            RepoPath = $normalized
            Length = $item.Length
        }
    }

    return $files | Sort-Object RepoPath
}

function Assert-NoSecrets($files) {
    $secretPattern = "sk-[A-Za-z0-9_-]{20,}|cfat_[A-Za-z0-9_-]{20,}|cfut_[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|[0-9]{8,}:[A-Za-z0-9_-]{30,}"
    $matches = @()

    foreach ($file in $files) {
        $name = Split-Path -Leaf $file.LocalPath
        if ($name -eq ".env") {
            continue
        }

        try {
            $matches += Select-String -LiteralPath $file.LocalPath -Pattern $secretPattern -ErrorAction SilentlyContinue
        } catch {
            # Binary files that cannot be scanned as text are still uploaded if they are not excluded.
        }
    }

    if ($matches) {
        Write-Host "Potential secrets found in these files:" -ForegroundColor Yellow
        $matches | Select-Object -ExpandProperty Path -Unique | ForEach-Object { Write-Host $_ }
        Fail "I stopped before uploading. Remove these secrets or move them into .env."
    }
}

function New-GitHubBlob($owner, $repo, $file) {
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $file.LocalPath))
    $content = [Convert]::ToBase64String($bytes)

    return Invoke-GitHubApi "Post" "/repos/$owner/$repo/git/blobs" @{
        content = $content
        encoding = "base64"
    }
}

function Initialize-EmptyRepository($owner, $repo, $branch) {
    Write-Host "Repository is empty. Initializing $branch branch first..."

    $content = ConvertTo-Base64Url "Initializing repository for automatic upload."
    Invoke-GitHubApi "Put" "/repos/$owner/$repo/contents/README.md" @{
        message = "Initialize repository"
        content = $content
        branch = $branch
    } | Out-Null

    Start-Sleep -Seconds 2
    $baseRef = Invoke-GitHubApi "Get" "/repos/$owner/$repo/git/ref/heads/$branch" $null $true
    if (-not $baseRef) {
        Fail "The repository was initialized, but GitHub did not create the branch yet. Wait one minute and run this uploader again."
    }

    return $baseRef
}

$script:githubToken = $env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($script:githubToken)) {
    $secureToken = Read-Host "Paste GitHub Fine-grained Personal Access Token" -AsSecureString
    $script:githubToken = Get-PlainTokenFromSecureString $secureToken
}

if ([string]::IsNullOrWhiteSpace($script:githubToken)) {
    Fail "GitHub token is required."
}

Write-Host "Checking GitHub token..."
$currentUser = Invoke-GitHubApi "Get" "/user"
Write-Host "GitHub user: $($currentUser.login)"

$repoInput = Read-Host "Repository [telegram-translator-bot]"
if ([string]::IsNullOrWhiteSpace($repoInput)) {
    $repoInput = "telegram-translator-bot"
}

$parsed = Parse-RepositoryInput $repoInput $currentUser.login
$owner = $parsed.owner
$repoName = $parsed.repo

Write-Host "Checking repository: $owner/$repoName"
$repoInfo = Invoke-GitHubApi "Get" "/repos/$owner/$repoName" $null $true
if (-not $repoInfo) {
    Write-Host "Repository was not found. I will try to create a private repository named $repoName..."
    $repoInfo = Invoke-GitHubApi "Post" "/user/repos" @{
        name = $repoName
        private = $true
        auto_init = $false
        description = "Telegram bot for Chinese to American English translation"
    } $true

    if (-not $repoInfo) {
        Fail "The token cannot access or create $owner/$repoName. Create this repository on GitHub, select it in the Fine-grained token, and set Contents: Read and write."
    }
}

if ($repoInfo.permissions) {
    $canPush = $repoInfo.permissions.push -or $repoInfo.permissions.admin -or $repoInfo.permissions.maintain
    if (-not $canPush) {
        Fail "This token can see the repository but cannot write to it. Set Repository permissions -> Contents -> Read and write for $owner/$repoName."
    }
}

$branch = $repoInfo.default_branch
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "main"
}

$files = @(Get-UploadFiles)
if ($files.Count -eq 0) {
    Fail "No files were found to upload."
}

Write-Host "Checking files for accidental secrets..."
Assert-NoSecrets $files

Write-Host "Checking branch: $branch"
$baseRef = Invoke-GitHubApi "Get" "/repos/$owner/$repoName/git/ref/heads/$branch" $null $true
if (-not $baseRef) {
    $baseRef = Initialize-EmptyRepository $owner $repoName $branch
}

$parents = @()
$baseTree = $null
if ($baseRef) {
    $baseCommitSha = $baseRef.object.sha
    $baseCommit = Invoke-GitHubApi "Get" "/repos/$owner/$repoName/git/commits/$baseCommitSha"
    $baseTree = $baseCommit.tree.sha
    $parents = @($baseCommitSha)
}

Write-Host "Preparing $($files.Count) files..."
$treeEntries = @()
$index = 0
foreach ($file in $files) {
    $index += 1
    Write-Host ("Uploading file {0}/{1}: {2}" -f $index, $files.Count, $file.RepoPath)
    $blob = New-GitHubBlob $owner $repoName $file

    $mode = "100644"
    if ($file.RepoPath -like "*.sh") {
        $mode = "100755"
    }

    $treeEntries += @{
        path = $file.RepoPath
        mode = $mode
        type = "blob"
        sha = $blob.sha
    }
}

Write-Host "Creating one GitHub commit..."
$treeBody = @{
    tree = $treeEntries
}
if ($baseTree) {
    $treeBody.base_tree = $baseTree
}

$newTree = Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/trees" $treeBody

$message = Read-Host "Commit message [Upload Telegram translator bot]"
if ([string]::IsNullOrWhiteSpace($message)) {
    $message = "Upload Telegram translator bot"
}

$commitBody = @{
    message = $message
    tree = $newTree.sha
}

if ($parents.Count -gt 0) {
    $commitBody.parents = $parents
}

$newCommit = Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/commits" $commitBody

if ($baseRef) {
    Write-Host "Updating branch..."
    Invoke-GitHubApi "Patch" "/repos/$owner/$repoName/git/refs/heads/$branch" @{
        sha = $newCommit.sha
        force = $false
    } | Out-Null
} else {
    Write-Host "Creating branch..."
    Invoke-GitHubApi "Post" "/repos/$owner/$repoName/git/refs" @{
        ref = "refs/heads/$branch"
        sha = $newCommit.sha
    } | Out-Null
}

Write-Host ""
Write-Host "SUCCESS: Upload complete."
Write-Host "Repository: https://github.com/$owner/$repoName"
Write-Host ""
