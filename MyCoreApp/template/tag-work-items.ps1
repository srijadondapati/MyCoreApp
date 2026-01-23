param (
    [Parameter(Mandatory = $true)]
    [string]$environment
)

# =========================================================
# SECTION 0: Basic configuration
# ========================================================

$org     = $env:ADO_ORG
$project = $env:ADO_PROJECT
$pat     = $env:ADO_PAT

#$envTag = "DeployedEnv:$environment"
$envTag = "DeployedEnv:$($environment.ToUpper())"

Write-Host "=========================================="
Write-Host "Azure DevOps Work Item Tag Update"
Write-Host "=========================================="
Write-Host "Environment Tag: $envTag"
Write-Host "Organization: $org"
Write-Host "Project: $project"

# =========================================================
# SECTION 1: Validate PAT
# =========================================================

if ([string]::IsNullOrWhiteSpace($pat)) {
    throw "ADO_PAT is missing. Check variable group 'workitem-tagging-secrets'."
}

# =========================================================
# SECTION 2: Auth header
# =========================================================

$basicAuth = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$pat")
)

$headers = @{
    Authorization = "Basic $basicAuth"
    "Content-Type" = "application/json-patch+json"
}

# =========================================================
# SECTION 3: Extract Work Item IDs from commit message
# =========================================================

$commitMsg = $env:BUILD_SOURCEVERSIONMESSAGE
Write-Host "Commit Message: $commitMsg"

$ids = [regex]::Matches($commitMsg, 'AB#(\d+)') |
       ForEach-Object { $_.Groups[1].Value } |
       Select-Object -Unique

Write-Host "Found work item IDs: $($ids -join ', ')"

if ($ids.Count -eq 0) {
    Write-Host "No work items found. Skipping."
    exit 0
}

# =========================================================
# SECTION 4: Counters
# =========================================================

$successCount = 0
$failureCount = 0

# =========================================================
# SECTION 5: Process each work item
# =========================================================

foreach ($id in $ids) {

    Write-Host ""
    Write-Host "➡️ Processing Work Item ID: $id"

    try {
        $url = "https://dev.azure.com/$org/$project/_apis/wit/workitems/$id?api-version=7.1-preview.3"

        $wi = Invoke-RestMethod -Method Get -Uri $url -Headers @{
            Authorization = "Basic $basicAuth"
        }

        $wiTitle     = $wi.fields.'System.Title'
        $existingTags = $wi.fields.'System.Tags'

        if (-not $existingTags) { $existingTags = "" }

        Write-Host "Title: $wiTitle"
        Write-Host "Current Tags: '$existingTags'"

        # Skip if tag already exists
        if ($existingTags -match [regex]::Escape($envTag)) {
            Write-Host "Already tagged with $envTag. Skipping."
            $successCount++
            continue
        }

        # Append tag
        if ([string]::IsNullOrWhiteSpace($existingTags)) {
            $newTags = $envTag
        } else {
            $newTags = "$existingTags; $envTag"
        }

        $patchBody = @(
            @{
                op    = "replace"
                path  = "/fields/System.Tags"
                value = $newTags
            }
        ) | ConvertTo-Json

        Invoke-RestMethod -Method Patch -Uri $url -Headers $headers -Body $patchBody

        Write-Host "Successfully updated Work Item $id"
        $successCount++

    } catch {
        Write-Host "Error updating Work Item $id"
        Write-Host $_.Exception.Message
        $failureCount++
    }
}

# =========================================================
# SECTION 6: Summary
# =========================================================

Write-Host "=========================================="
Write-Host "Update Summary"
Write-Host "Success: $successCount"
Write-Host "Failed:  $failureCount"
Write-Host "Total:   $($ids.Count)"
Write-Host "=========================================="

if ($failureCount -gt 0) {
    Write-Host "##vso[task.logissue type=warning]Some work items failed to update"
}
