param(
    [string]$Organization,
    [string]$Project,
    [string]$PersonalAccessToken,
    [string]$EnvironmentTag,
    [string]$CommitMessage
)

# =========================================================
# SECTION 0: Basic configuration validation
# =========================================================

Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tag Update"
Write-Host "=========================================="
Write-Host "Environment Tag: $EnvironmentTag"
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Organization parameter is required."
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Project parameter is required."
}

if ([string]::IsNullOrWhiteSpace($PersonalAccessToken)) {
    throw "Personal Access Token is required."
}

if ([string]::IsNullOrWhiteSpace($EnvironmentTag)) {
    throw "Environment Tag is required."
}

# =========================================================
# SECTION 1: Build authentication header
# =========================================================

# Azure DevOps requires Basic Auth with Base64-encoded PAT
$basicAuth = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken")
)

$headers = @{
    Authorization = "Basic $basicAuth"
    "Content-Type" = "application/json-patch+json"
}

# =========================================================
# SECTION 2: Extract Work Item IDs from commit message
# =========================================================

Write-Host "Commit Message: $CommitMessage"

# Extract work item IDs referenced using AB#<id>
$ids = [regex]::Matches($CommitMessage, 'AB#(\d+)') |
       ForEach-Object { $_.Groups[1].Value } |
       Select-Object -Unique

# Log discovered work item IDs
Write-Host "Found work item IDs: $($ids -join ', ')"

# Exit early if no work items are referenced
if ($ids.Count -eq 0) {
    Write-Host "No work items found. Skipping."
    exit 0
}

# =========================================================
# SECTION 3: Initialize counters
# =========================================================
$successCount = 0
$failureCount = 0

# =========================================================
# SECTION 4: Process each work item
# =========================================================
foreach ($id in $ids) {

    Write-Host ""
    Write-Host "➡️ Processing Work Item ID: $id"
    Write-Host "----------------------------------------"
    
    try {
        # -----------------------------------------------------
        # STEP 4a: Build Work Item REST API URL
        # -----------------------------------------------------
        $url = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($id)?api-version=7.1-preview.3"
        Write-Host "API URL: $url"
        
        # -----------------------------------------------------
        # STEP 4b: Read existing work item
        # -----------------------------------------------------
        $wi = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

        # Extract work item title and existing tags
        $wiTitle = $wi.fields.'System.Title'
        $existingTags = $wi.fields.'System.Tags'

        # Normalize empty tags
        if (-not $existingTags) { $existingTags = "" }

        Write-Host "Title: $wiTitle"
        Write-Host "Current Tags: '$existingTags'"
        
        # -----------------------------------------------------
        # STEP 4c: Skip update if tag already exists
        # -----------------------------------------------------
        if ($existingTags -match [regex]::Escape($EnvironmentTag)) { 
            Write-Host "✅ Already tagged with: $EnvironmentTag"
            $successCount++
            continue 
        }

        # -----------------------------------------------------
        # STEP 4d: Calculate new tags (append behavior)
        # -----------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($existingTags)) {
            $newTags = $EnvironmentTag
        } else {
            $newTags = "$existingTags; $EnvironmentTag"
        }

        Write-Host "New Tags: '$newTags'"

        # -----------------------------------------------------
        # STEP 4e: Create JSON PATCH document
        # -----------------------------------------------------
        $patchDocument = '[{"op":"replace","path":"/fields/System.Tags","value":"' + $newTags + '"}]'
        
        Write-Host "Patch Document: $patchDocument"
        
        # -----------------------------------------------------
        # STEP 4f: Send PATCH request to update work item
        # -----------------------------------------------------
        Write-Host "Sending PATCH request..."
        $response = Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patchDocument
        
        Write-Host "✅ Successfully updated Work Item $id"
        Write-Host "   Title: $wiTitle"
        Write-Host "   New Tags: $($response.fields.'System.Tags')"
        $successCount++
        
    } catch {
        # -----------------------------------------------------
        # STEP 4g: Error handling for work item update
        # -----------------------------------------------------
        Write-Host "❌ Error updating Work Item $id"
        Write-Host "   Error Message: $($_.Exception.Message)"
        
        # Attempt to read detailed error response from API
        try {
            if ($_.Exception.Response) {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $errorStream.Position = 0
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Host "   Error Response: $errorBody"
            }
        } catch {
            Write-Host "   Could not read error response"
        }
        
        $failureCount++
    }
}

# =========================================================
# SECTION 5: Final summary
# =========================================================
Write-Host ""
Write-Host "=========================================="
Write-Host "Update Summary:"
Write-Host "✅ Successfully updated: $successCount"
Write-Host "❌ Failed: $failureCount"
Write-Host "Total processed: $($ids.Count)"
Write-Host "=========================================="

# Exit with error code if any failures occurred
if ($failureCount -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed to update"
    exit 1
}

exit 0
