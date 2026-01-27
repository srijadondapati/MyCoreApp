# =========================================================
# Azure DevOps Work Item Tags
# =========================================================
# This script updates Azure DevOps work items with deployment
# environment tags (e.g., DeployedEnv:DEV) based on AB#123
# references found in the latest git commit message.
# =========================================================

param(
  # Azure DevOps organization name (e.g., my-org)
  [Parameter(Mandatory)]
  [string]$Organization,

  # Azure DevOps project name
  [Parameter(Mandatory)]
  [string]$Project,

  # Deployment environment name (e.g., dev, qa, prod)
  [Parameter(Mandatory)]
  [string]$EnvironmentTag
)

# Ensure console output supports UTF-8 characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# =========================================================
# SECTION 0: Basic configuration validation
# =========================================================

# Display script header in logs
Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tag Update"
Write-Host "=========================================="

# Validate Organization parameter
if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Organization parameter is required."
}

# Validate Project parameter
if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Project parameter is required."
}

# Validate EnvironmentTag parameter
if ([string]::IsNullOrWhiteSpace($EnvironmentTag)) {
    throw "Environment Tag is required."
}

# ---------------------------------------------------------
# Normalize environment tag
# - Converts environment name to uppercase
# - Prefixes with 'DeployedEnv:' for consistency
# ---------------------------------------------------------
# $EnvironmentTag = $EnvironmentTag.ToUpperInvariant()
$EnvironmentTag = "DeployedEnv:$($EnvironmentTag.ToUpperInvariant())"

# Log resolved configuration values
Write-Host "Environment Tag: $EnvironmentTag"
Write-Host "Organization: $Organization"
Write-Host "Project: $Project"

# =========================================================
# SECTION 1: OAuth authentication header
# =========================================================

# Retrieve the Azure DevOps OAuth token injected by the pipeline
$accessToken = $env:SYSTEM_ACCESSTOKEN

# Fail if OAuth token is missing (usually pipeline misconfiguration)
if ([string]::IsNullOrWhiteSpace($accessToken)) {
  throw "System.AccessToken is missing. Ensure YAML passes env:SYSTEM_ACCESSTOKEN: $(System.AccessToken) and OAuth access is enabled."
}

# Build REST API headers
# - Authorization uses Bearer token
# - Content-Type is JSON Patch (required for work item updates)
$headers = @{
  Authorization  = "Bearer $accessToken"
  "Content-Type" = "application/json-patch+json"
}

# =========================================================
# SECTION 2: Read FULL commit message from git
# =========================================================

# Read the full commit message body of the latest commit
$commitMessage = git log -1 --pretty=%B

# Log the commit message for traceability
Write-Host "Full Commit Message: $commitMessage"

# Extract work item references of the form AB#123
# - Uses regex to find all matches
# - Extracts only the numeric ID
# - Removes duplicates
$ids = [regex]::Matches($commitMessage, 'AB#(\d+)') |
       ForEach-Object { $_.Groups[1].Value } |
       Select-Object -Unique

# Log discovered work item IDs
Write-Host "Found work item IDs: $($ids -join ', ')"

# Exit early if no work items were referenced
if ($ids.Count -eq 0) {
    Write-Host "No work items found. Skipping."
    exit 0
}

# =========================================================
# SECTION 3: Initialize counters
# =========================================================

# Count successful updates
$successCount = 0

# Count failed updates
$failureCount = 0

# Count skipped work items (already tagged)
$skippedCount = 0

# =========================================================
# SECTION 4: Process each work item
# =========================================================

foreach ($id in $ids) {

    # Visual separation for each work item in logs
    Write-Host ""
    Write-Host "-> Processing Work Item ID: $id"
    Write-Host "----------------------------------------"
    
    try {
        # -----------------------------------------------------
        # STEP 4a: Build Work Item REST API URL
        # -----------------------------------------------------
        # Uses Azure DevOps Work Item Tracking API
        $url = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/$($id)?api-version=7.1-preview.3"
        Write-Host "API URL: $url"
        
        # -----------------------------------------------------
        # STEP 4b: Read existing work item
        # -----------------------------------------------------
        # Retrieve the current state of the work item
        $wi = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

        # Extract work item title
        $wiTitle = $wi.fields.'System.Title'

        # Extract existing tags (semicolon-delimited string)
        $existingTags = $wi.fields.'System.Tags'

        # Normalize null/empty tags to empty string
        if (-not $existingTags) { $existingTags = "" }

        # Log work item details
        Write-Host "Title: $wiTitle"
        Write-Host "Current Tags: '$existingTags'"
        
        # -----------------------------------------------------
        # STEP 4c: Skip update if tag already exists
        # -----------------------------------------------------
        # Prevents duplicate environment tags
        if ($existingTags -match [regex]::Escape($EnvironmentTag)) { 
            Write-Host "[SKIP] Already tagged with: $EnvironmentTag"
            $skippedCount++
            continue 
        }

        # -----------------------------------------------------
        # STEP 4d: Calculate new tags (append behavior)
        # -----------------------------------------------------
        # Append new environment tag to existing tags
        if ([string]::IsNullOrWhiteSpace($existingTags)) {
            $newTags = $EnvironmentTag
        } else {
            $newTags = "$existingTags; $EnvironmentTag"
        }

        # Log final tag value
        Write-Host "New Tags: '$newTags'"

        # -----------------------------------------------------
        # STEP 4e: Create JSON PATCH document
        # -----------------------------------------------------
        # Uses "replace" to overwrite System.Tags field
        $patchDocument = '[{"op":"replace","path":"/fields/System.Tags","value":"' + $newTags + '"}]'
        
        Write-Host "Patch Document: $patchDocument"
        
        # -----------------------------------------------------
        # STEP 4f: Send PATCH request to update work item
        # -----------------------------------------------------
        Write-Host "Sending PATCH request..."
        $response = Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patchDocument
        
        # Log success details
        Write-Host "[SUCCESS] Updated Work Item $id"
        Write-Host "  Title: $wiTitle"
        Write-Host "  New Tags: $($response.fields.'System.Tags')"

        $successCount++
        
    } catch {
        # -----------------------------------------------------
        # STEP 4g: Error handling for work item update
        # -----------------------------------------------------
        Write-Host "[ERROR] Failed to update Work Item $id"
        Write-Host "  Error Message: $($_.Exception.Message)"
        
        # Attempt to read detailed error response from Azure DevOps API
        try {
            if ($_.Exception.Response) {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $errorStream.Position = 0
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Host "  Error Response: $errorBody"
            }
        } catch {
            Write-Host "  Could not read error response"
        }
        
        $failureCount++
    }
}

# =========================================================
# SECTION 5: Final summary
# =========================================================

# Output final execution summary
Write-Host ""
Write-Host "=========================================="
Write-Host "Update Summary:"
Write-Host "[SUCCESS] Updated: $successCount"
Write-Host "[SKIPPED] Already tagged: $skippedCount"
Write-Host "[ERROR] Failed: $failureCount"
Write-Host "Total referenced: $($ids.Count)"
Write-Host "=========================================="

# Fail the pipeline if any work items failed to update
if ($failureCount -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed to update"
    exit 1
}

# Exit successfully
exit 0
