# =========================================================
# Update-WorkItemTags.ps1
# =========================================================
# Purpose:
#   - Discover Azure DevOps work items (AB#123)
#   - From commit messages, ADO PR metadata, or GitHub PRs
#   - Apply a deployment environment tag to each work item
#
# Compatible with:
#   - Windows PowerShell 5.1 (ADO hosted agents)
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
# SECTION 0: Validation and Setup
# =========================================================

Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tag Update"
Write-Host "=========================================="

if (
    [string]::IsNullOrWhiteSpace($Organization) -or
    [string]::IsNullOrWhiteSpace($Project) -or
    [string]::IsNullOrWhiteSpace($EnvironmentTag)
) {
    throw "Organization, Project, and EnvironmentTag are required."
}

# Normalize environment tag format
$EnvironmentTag = "DeployedEnv:" + $EnvironmentTag.ToUpperInvariant()

Write-Host "Organization    : $Organization"
Write-Host "Project         : $Project"
Write-Host "Environment Tag : $EnvironmentTag"
Write-Host ""

# =========================================================
# SECTION 1: Azure DevOps Authentication
# =========================================================

$accessToken = $env:SYSTEM_ACCESSTOKEN
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    Write-Host "ERROR: System.AccessToken is not available."
    Write-Host "Enable 'Allow scripts to access OAuth token'."
    exit 1
}

$headers = @{
    Authorization  = "Bearer " + $accessToken
    "Content-Type" = "application/json-patch+json"
}

Write-Host "Authentication successful."
Write-Host ""

# =========================================================
# SECTION 2: Work Item Discovery Functions
# =========================================================

# Extract work item IDs from the last git commit message
function Get-WorkItemsFromCommit {

    Write-Host "Checking commit message..."

    try {
        $message = git log -1 --pretty=%B

        return (
            [regex]::Matches($message, 'AB#(\d+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
        )
    }
    catch {
        return @()
    }
}

# Extract work item IDs from Azure DevOps PR environment variables
function Get-WorkItemsFromADO {

    Write-Host "Checking Azure DevOps PR variables..."

    $title = $env:SYSTEM_PULLREQUEST_SOURCECOMMITMESSAGE
    $description = $env:SYSTEM_PULLREQUEST_DESCRIPTION

    if (
        [string]::IsNullOrWhiteSpace($title) -and
        [string]::IsNullOrWhiteSpace($description)
    ) {
        return @()
    }

    $text = $title + " " + $description

    return (
        [regex]::Matches($text, 'AB#(\d+)') |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique
    )
}

# Extract work item IDs from a GitHub PR (merge commit)
function Get-WorkItemsFromGitHubPR {

    Write-Host "Checking GitHub PR (if applicable)..."

    $ids = @()

    $commitMessage = git log -1 --pretty=%B
    if ($commitMessage -notmatch "Merge pull request #(\d+)") {
        return $ids
    }

    $prNumber = $matches[1]

    # Resolve repository name
    $repoName = $env:BUILD_REPOSITORY_NAME
    $repoUri  = $env:BUILD_REPOSITORY_URI
    $repo     = ""

    if ($repoName -match "^[^/]+/[^/]+$") {
        $repo = $repoName
    }
    elseif ($repoUri -match "github\.com/([^/]+)/") {
        $repo = $matches[1] + "/" + $repoName
    }

    if ([string]::IsNullOrWhiteSpace($repo)) {
        return $ids
    }

    # GitHub token must be supplied explicitly
    $githubToken = $env:GITHUB_TOKEN
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        return $ids
    }

    $githubHeaders = @{
        Authorization = "Bearer " + $githubToken
        Accept        = "application/vnd.github.v3+json"
    }

    $url = "https://api.github.com/repos/$repo/pulls/$prNumber"

    try {
        $pr = Invoke-RestMethod -Uri $url -Headers $githubHeaders -ErrorAction Stop
        $text = $pr.title + " " + $pr.body

        $ids = (
            [regex]::Matches($text, 'AB#(\d+)') |
            ForEach-Object { $_.Groups[1].Value } |
            Select-Object -Unique
        )
    }
    catch {
        # Ignore GitHub errors silently
    }

    return $ids
}

# =========================================================
# SECTION 3: Aggregate Work Item IDs
# =========================================================

Write-Host "Collecting work item references..."
Write-Host ""

$allIds = @()
$allIds += Get-WorkItemsFromCommit
$allIds += Get-WorkItemsFromADO
$allIds += Get-WorkItemsFromGitHubPR

$workItemIds = $allIds | Select-Object -Unique

Write-Host "Total work items found: $($workItemIds.Count)"
Write-Host ""

if ($workItemIds.Count -eq 0) {
    Write-Host "No work items found. Exiting."
    exit 0
}

# =========================================================
# SECTION 4: Apply Environment Tag
# =========================================================

$success = 0
$skipped = 0
$failed  = 0

foreach ($id in $workItemIds) {

    Write-Host "Processing work item $id..."

    try {
        $url = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$id?api-version=7.1-preview.3"
        $wi  = Invoke-RestMethod -Uri $url -Headers $headers

        $existingTags = $wi.fields.'System.Tags'
        if ([string]::IsNullOrWhiteSpace($existingTags)) {
            $existingTags = ""
        }

        if ($existingTags -match [regex]::Escape($EnvironmentTag)) {
            $skipped++
            continue
        }

        if ($existingTags) {
            $newTags = $existingTags + "; " + $EnvironmentTag
        } else {
            $newTags = $EnvironmentTag
        }

        $patch = @(
            @{
                op    = 'replace'
                path  = '/fields/System.Tags'
                value = $newTags
            }
        ) | ConvertTo-Json -Depth 3

        Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patch
        $success++
    }
    catch {
        $failed++
    }
}

# =========================================================
# SECTION 5: Summary
# =========================================================

Write-Host "=========================================="
Write-Host "Update Summary"
Write-Host "=========================================="
Write-Host "Updated : $success"
Write-Host "Skipped : $skipped"
Write-Host "Failed  : $failed"
Write-Host "Total   : $($workItemIds.Count)"
Write-Host "=========================================="

if ($failed -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed to update"
    exit 1
}

Write-Host "All work items processed successfully."
exit 0
