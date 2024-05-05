# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\xx_Sandkasten"
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa" # Securely pass your PAT

# Base URI for Azure DevOps REST API calls
$baseUri = "https://dev.azure.com/$sourceOrg"

# Headers for authentication
$headers = @{
    "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
    "Content-Type" = "application/json"
}

# Function to get all work items from the source project and area
function Get-WorkItems {
    $wiql = @{
        "query" = "SELECT [System.Id], [System.Title], [System.State], [System.AreaPath] FROM WorkItems WHERE [System.AreaPath] = '$sourceArea'"
    }
    
    $uri = "$baseUri/$sourceProject/_apis/wit/wiql?api-version=6.0"
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($wiql | ConvertTo-Json)
    
    # Extract work item IDs
    $ids = $response.workItems.id -join ","
    
    # Get detailed info for each work item
    $detailUri = "$baseUri/$sourceProject/_apis/wit/workitems?ids=$ids&`$expand=fields,relations&api-version=6.0"
    $workItems = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
    return $workItems
}

# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    $uri = "$baseUri/$targetProject/_apis/wit/workitems/`$$workItem.fields['System.WorkItemType']?api-version=6.0"
    
    $body = @(
        @{
            "op" = "add"
            "path" = "/fields/System.Title"
            "value" = $workItem.fields['System.Title']
        },
        @{
            "op" = "add"
            "path" = "/fields/System.Description"
            "value" = $workItem.fields['System.Description']
        }
        # Add more fields as necessary
    )

    $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body ($body | ConvertTo-Json)
    return $response
}

# Main script execution
$workItems = Get-WorkItems
foreach ($wi in $workItems) {
    $newWi = Create-WorkItem $wi
    Write-Host "Created new work item with ID: $($newWi.id)"
}
