# =========================================================
# Update-WorkItemTags-FIXED.ps1
# =========================================================
# FIXED: Properly gets pipeline variables
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
# SECTION 0: Configuration
# =========================================================

Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tagging"
Write-Host "=========================================="

# Validate parameters
if ([string]::IsNullOrWhiteSpace($Organization) -or 
    [string]::IsNullOrWhiteSpace($Project) -or 
    [string]::IsNullOrWhiteSpace($EnvironmentTag)) {
    throw "All parameters are required"
}

$EnvironmentTag = "DeployedEnv:$($EnvironmentTag.ToUpperInvariant())"

Write-Host "Environment Tag: $EnvironmentTag"
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"
Write-Host ""

# =========================================================
# SECTION 1: Authentication
# =========================================================

$accessToken = $env:SYSTEM_ACCESSTOKEN
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    Write-Host "❌ ERROR: System.AccessToken is missing!"
    Write-Host "💡 Enable OAuth token access in pipeline settings"
    exit 1
}

Write-Host "✅ Using System.AccessToken"
$headers = @{
    Authorization  = "Bearer $accessToken"
    "Content-Type" = "application/json-patch+json"
}

# =========================================================
# SECTION 2: Work Item Extraction Functions
# =========================================================

function Get-WorkItemsFromCommit {
    Write-Host "🔍 Method 1: Checking git commit message..."
    
    $ids = @()
    try {
        $commitMsg = git log -1 --pretty=%B
        Write-Host "   Commit: $commitMsg"
        
        $ids = [regex]::Matches($commitMsg, 'AB#(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        
        if ($ids.Count -gt 0) {
            Write-Host "   ✅ Found in commit: $($ids -join ', ')"
        }
    } catch {
        Write-Host "   ⚠️ Could not get commit message"
    }
    
    return $ids
}

function Get-WorkItemsFromADO {
    Write-Host "🔍 Method 2: Checking Azure DevOps PR variables..."
    
    $ids = @()
    
    # FIXED: Get from environment variables, not $(...)
    $prTitle = $env:SYSTEM_PULLREQUEST_SOURCECOMMITMESSAGE
    $prDescription = $env:SYSTEM_PULLREQUEST_DESCRIPTION
    
    Write-Host "   PR Title: $prTitle"
    Write-Host "   PR Description: $prDescription"
    
    if (-not [string]::IsNullOrWhiteSpace($prTitle) -or 
        -not [string]::IsNullOrWhiteSpace($prDescription)) {
        
        $prText = $prTitle + " " + $prDescription
        $ids = [regex]::Matches($prText, 'AB#(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        
        if ($ids.Count -gt 0) {
            Write-Host "   ✅ Found in ADO PR: $($ids -join ', ')"
        }
    }
    
    return $ids
}

function Get-WorkItemsFromGitHubPR {
    Write-Host "🔍 Method 3: Checking GitHub PR..."
    
    $ids = @()
    
    # Check if this is a GitHub merge commit
    $commitMsg = git log -1 --pretty=%B
    if ($commitMsg -match "Merge pull request #(\d+)") {
        $prNumber = $matches[1]
        Write-Host "   Detected GitHub PR #$prNumber"
        
        # ==========================================
        # FIX 1: Get repository name from environment
        # ==========================================
        $repo = ""
        
        # Method 1: Try environment variable
        $repoName = $env:BUILD_REPOSITORY_NAME
        Write-Host "   BUILD_REPOSITORY_NAME: $repoName"
        
        if (-not [string]::IsNullOrWhiteSpace($repoName)) {
            # Check if it's already in "owner/repo" format
            if ($repoName -match "^[^/]+/[^/]+$") {
                $repo = $repoName
                Write-Host "   Repository: $repo"
            } else {
                # Try to get owner from BUILD_REPOSITORY_URI
                $repoUri = $env:BUILD_REPOSITORY_URI
                Write-Host "   BUILD_REPOSITORY_URI: $repoUri"
                
                if (-not [string]::IsNullOrWhiteSpace($repoUri) -and $repoUri -match "github\.com/([^/]+)/") {
                    $owner = $matches[1]
                    $repo = "$owner/$repoName"
                    Write-Host "   Repository (constructed): $repo"
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($repo)) {
            Write-Host "   ❌ Could not determine GitHub repository"
            return $ids
        }
        
        # ==========================================
        # FIX 2: GitHub token from environment
        # ==========================================
        $githubToken = $env:GITHUB_TOKEN
        if ([string]::IsNullOrWhiteSpace($githubToken)) {
            Write-Host "   ❌ GITHUB_TOKEN is REQUIRED for GitHub PR extraction"
            Write-Host "   💡 Add GitHubToken to your variable group"
            return $ids
        }
        
        Write-Host "   Fetching PR #$prNumber from $repo..."
        
        # ==========================================
        # FIX 3: Use Bearer token
        # ==========================================
        $githubHeaders = @{
            "Authorization" = "Bearer $githubToken"
            "Accept" = "application/vnd.github.v3+json"
        }
        
        $prUrl = "https://api.github.com/repos/$repo/pulls/$prNumber"
        
        try {
            $prData = Invoke-RestMethod -Uri $prUrl -Headers $githubHeaders -ErrorAction Stop
            
            # Extract from PR title and body
            $prText = $prData.title + " " + $prData.body
            $ids = [regex]::Matches($prText, 'AB#(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            
            if ($ids.Count -gt 0) {
                Write-Host "   ✅ Found in GitHub PR: $($ids -join ', ')"
            } else {
                Write-Host "   ℹ️ No work items in GitHub PR"
            }
            
        } catch {
            Write-Host "   ❌ GitHub API error: $($_.Exception.Message)"
            
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                Write-Host "   Status Code: $statusCode"
                
                if ($statusCode -eq 404) {
                    Write-Host "   💡 Repository '$repo' not found or no access"
                } elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
                    Write-Host "   💡 GitHub token invalid or insufficient permissions"
                }
            }
        }
    } else {
        Write-Host "   ℹ️ Not a GitHub merge commit"
    }
    
    return $ids
}

# =========================================================
# SECTION 3: Main Execution
# =========================================================

Write-Host "📋 Gathering work item references..."
Write-Host ""

# Try all methods
$commitIds = Get-WorkItemsFromCommit
$adoPrIds = Get-WorkItemsFromADO
$githubPrIds = Get-WorkItemsFromGitHubPR

# Combine all IDs
$allWorkItemIds = @()
$allWorkItemIds += $commitIds
$allWorkItemIds += $adoPrIds
$allWorkItemIds += $githubPrIds

$uniqueWorkItemIds = $allWorkItemIds | Select-Object -Unique

Write-Host ""
Write-Host "📊 COLLECTION SUMMARY:"
Write-Host "   From commit: $($commitIds.Count)"
Write-Host "   From ADO PR: $($adoPrIds.Count)"
Write-Host "   From GitHub PR: $($githubPrIds.Count)"
Write-Host "   Unique total: $($uniqueWorkItemIds.Count)"
Write-Host ""

if ($uniqueWorkItemIds.Count -eq 0) {
    Write-Host "❌ No work items found"
    Write-Host ""
    Write-Host "💡 For RELIABLE GitHub PR support:"
    Write-Host "   1. Add GitHubToken to variable group (MANDATORY)"
    Write-Host "   2. Ensure token has 'repo' scope"
    Write-Host "   3. Put AB# in PR title (not just description)"
    exit 0
}

Write-Host "✅ Found work items: $($uniqueWorkItemIds -join ', ')"

# =========================================================
# SECTION 4: Tagging Logic
# =========================================================

$successCount = 0
$failureCount = 0
$skippedCount = 0

Write-Host ""
Write-Host "🔄 Processing work items..."
Write-Host ""

foreach ($id in $uniqueWorkItemIds) {
    Write-Host "➡️ Processing Work Item ID: $id"
    Write-Host "----------------------------------------"
    
    try {
        $url = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($id)?api-version=7.1-preview.3"
        
        $wi = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
        $existingTags = $wi.fields.'System.Tags'
        if ([string]::IsNullOrWhiteSpace($existingTags)) { $existingTags = "" }
        
        Write-Host "   Title: $($wi.fields.'System.Title')"
        Write-Host "   Current Tags: '$existingTags'"
        
        if ($existingTags -match [regex]::Escape($EnvironmentTag)) { 
            Write-Host "   ✅ Already tagged"
            $skippedCount++
            continue 
        }
        
        $newTags = if ([string]::IsNullOrWhiteSpace($existingTags)) { $EnvironmentTag } else { "$existingTags; $EnvironmentTag" }
        
        $patchDoc = '[{"op":"replace","path":"/fields/System.Tags","value":"' + $newTags + '"}]'
        
        $response = Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patchDoc
        
        Write-Host "   ✅ Updated successfully"
        $successCount++
        
    } catch {
        Write-Host "   ❌ Error: $($_.Exception.Message)"
        $failureCount++
    }
    
    Write-Host ""
}

# =========================================================
# SECTION 5: Summary
# =========================================================

Write-Host "=========================================="
Write-Host "📊 UPDATE SUMMARY"
Write-Host "=========================================="
Write-Host "✅ Successfully updated: $successCount"
Write-Host "⏭️  Skipped (already tagged): $skippedCount"
Write-Host "❌ Failed: $failureCount"
Write-Host "📋 Total referenced: $($uniqueWorkItemIds.Count)"
Write-Host "=========================================="

if ($failureCount -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed to update"
    exit 1
}

Write-Host "🎉 All work items processed successfully!"
exit 0
