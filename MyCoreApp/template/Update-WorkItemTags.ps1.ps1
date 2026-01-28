# =========================================================
# Update-WorkItemTags.ps1
# ---------------------------------------------------------
# Purpose:
#   - Detect Azure DevOps Work Item IDs (AB#123)
#   - From commit messages, ADO PR metadata, or GitHub PRs
#   - Apply an environment deployment tag to each work item
#
# Requirements:
#   - Pipeline OAuth token enabled (System.AccessToken)
#   - Optional: GITHUB_TOKEN for GitHub PR inspection
# =========================================================

param(
    [Parameter(Mandatory)]
    [string]$Organization,

    [Parameter(Mandatory)]
    [string]$Project,

    [Parameter(Mandatory)]
    [string]$EnvironmentTag
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# =========================================================
# SECTION 0: Initialization & Validation
# =========================================================

Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tagging"
Write-Host "=========================================="

if (
    [string]::IsNullOrWhiteSpace($Organization) -or
    [string]::IsNullOrWhiteSpace($Project) -or
    [string]::IsNullOrWhiteSpace($EnvironmentTag)
) {
    throw "Organization, Project, and EnvironmentTag are required."
}

# Normalize environment tag
$EnvironmentTag = "DeployedEnv:$($EnvironmentTag.ToUpperInvariant())"

Write-Host "Organization    : $Organization"
Write-Host "Project         : $Project"
Write-Host "Environment Tag : $EnvironmentTag"
Write-Host ""

# =========================================================
# SECTION 1: Azure DevOps Authentication
# =========================================================

$accessToken = $env:SYSTEM_ACCESSTOKEN
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    Write-Host "❌ System.AccessToken is missing"
    Write-Host "💡 Enable 'Allow scripts to access OAuth token'"
    exit 1
}

$headers = @{
    Authorization  = "Bearer $accessToken"
    "Content-Type" = "application/json-patch+json"
}

Write-Host "✅ Using System.AccessToken"

# =========================================================
# SECTION 2: Work Item Discovery Functions
# =========================================================

function Get-WorkItemsFromCommit {
    Write-Host "🔍 Method 1: Commit message"

    try {
        $commitMsg = git log -1 --pretty=%B
        Write-Host "   Commit: $commitMsg"

        return (
            [regex]::Matches($commitMsg, 'AB#(\d+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
        )
    }
    catch {
        Write-Host "   ⚠️ Unable to read commit message"
        return @()
    }
}

function Get-WorkItemsFromADO {
    Write-Host "🔍 Method 2: Azure DevOps PR variables"

    $prTitle       = $env:SYSTEM_PULLREQUEST_SOURCECOMMITMESSAGE
    $prDescription = $env:SYSTEM_PULLREQUEST_DESCRIPTION

    Write-Host "   PR Title      : $prTitle"
    Write-Host "   PR Description: $prDescription"

    if (
        [string]::IsNullOrWhiteSpace($prTitle) -and
        [string]::IsNullOrWhiteSpace($prDescription)
    ) {
        return @()
    }

    $text = "$prTitle $prDescription"

    return (
        [regex]::Matches($text, 'AB#(\d+)') |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique
    )
}

function Get-WorkItemsFromGitHubPR {
    Write-Host "🔍 Method 3: GitHub PR (merge commit inspection)"

    $ids = @()

    $commitMsg = git log -1 --pretty=%B
    if ($commitMsg -notmatch "Merge pull request #(\d+)") {
        Write-Host "   ℹ️ Not a GitHub merge commit"
        return $ids
    }

    $prNumber = $matches[1]
    Write-Host "   Detected GitHub PR #$prNumber"

    # Resolve repository name
    $repoName = $env:BUILD_REPOSITORY_NAME
    $repoUri  = $env:BUILD_REPOSITORY_URI
    $repo     = ""

    if ($repoName -match "^[^/]+/[^/]+$") {
        $repo = $repoName
    }
    elseif ($repoUri -match "github\.com/([^/]+)/") {
        $repo = "$($matches[1])/$repoName"
    }

    if ([string]::IsNullOrWhiteSpace($repo)) {
        Write-Host "   ❌ Unable to determine GitHub repository"
        return $ids
    }

    $githubToken = $env:GITHUB_TOKEN
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        Write-Host "   ❌ GITHUB_TOKEN not provided"
        return $ids
    }

    $githubHeaders = @{
        Authorization = "Bearer $githubToken"
        Accept        = "application/vnd.github.v3+json"
    }

    $prUrl = "https://api.github.com/repos/$repo/pulls/$prNumber"

    try {
        $pr = Invoke-RestMethod -Uri $prUrl -Headers $githubHeaders -ErrorAction Stop
        $text = "$($pr.title) $($pr.body)"

        $ids = (
            [regex]::Matches($text, 'AB#(\d+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
        )
    }
    catch {
        Write-Host "   ❌ GitHub API error: $($_.Exception.Message)"
    }

    return $ids
}

# =========================================================
# SECTION 3: Collect All Work Item IDs
# =========================================================

Write-Host ""
Write-Host "📋 Collecting work items..."

$allIds = @()
$allIds += Get-WorkItemsFromCommit
$allIds += Get-WorkItemsFromADO
$allIds += Get-WorkItemsFromGitHubPR

$workItemIds = $allIds | Select-Object -Unique

Write-Host "   Total unique work items: $($workItemIds.Count)"
Write-Host ""

if ($workItemIds.Count -eq 0) {
    Write-Host "❌ No work items found"
    exit 0
}

# =========================================================
# SECTION 4: Apply Tags to Work Items
# =========================================================

$success = 0
$skipped = 0
$failed  = 0

foreach ($id in $workItemIds) {

    Write-Host "➡️ Work Item $id"

    try {
        $url = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$id?api-version=7.1-preview.3"
        $wi  = Invoke-RestMethod -Uri $url -Headers $headers

        $existingTags = $wi.fields.'System.Tags'
        if ([string]::IsNullOrWhiteSpace($existingTags)) {
            $existingTags = ""
        }

        if ($existingTags -match [regex]::Escape($EnvironmentTag)) {
            Write-Host "   ⏭️ Already tagged"
            $skipped++
            continue
        }

        $newTags = if ($existingTags) {
            "$existingTags; $EnvironmentTag"
        } else {
            $EnvironmentTag
        }

        $patch = @(
            @{
                op    = "replace"
                path  = "/fields/System.Tags"
                value = $newTags
            }
        ) | ConvertTo-Json -Depth 3

        Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patch
        Write-Host "   ✅ Updated"
        $success++
    }
    catch {
        Write-Host "   ❌ Failed: $($_.Exception.Message)"
        $failed++
    }
}

# =========================================================
# SECTION 5: Final Summary
# =========================================================

Write-Host "=========================================="
Write-Host "RESULT SUMMARY"
Write-Host "=========================================="
Write-Host "Updated : $success"
Write-Host "Skipped : $skipped"
Write-Host "Failed  : $failed"
Write-Host "Total   : $($workItemIds.Count)"
Write-Host "=========================================="

if ($failed -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed"
    exit 1
}

Write-Host "🎉 All work items processed successfully"
exit 0
