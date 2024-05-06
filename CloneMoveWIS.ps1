# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa"  # Securely pass your PAT

# Base URI for Azure DevOps REST API calls
$baseUri = "https://dev.azure.com/$sourceOrg"

# Headers for authentication
$headers = @{
    "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
}

# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    $workItemType = $workItem.fields.'System.WorkItemType'
    # Correctly embed the work item type in the URI
    $uri = "$baseUri/$targetProject/_apis/wit/workitems/`$$($WorkItemType)?validateOnly=True&bypassRules=True&suppressNotifications=True&`$expand=fields&api-version=api-version=7.2-preview.3"

    # Define default values for required fields to ensure they are not null
    $title = if ($workItem.fields.'System.Title') { $workItem.fields.'System.Title' } else { "Default Title" }
    $state = if ($workItem.fields.'System.State') { $workItem.fields.'System.State' } else { "New" }
    $description = $workItem.fields.'System.Description'

    # Construct the body of the POST request
    $body = @(
        @{
            "op" = "add"
            "path" = "/fields/System.Title"
            "value" = $title
        },
        @{
            "op" = "add"
            "path" = "/fields/System.State"
            "value" = $state
        },
        @{
            "op" = "add"
            "path" = "/fields/System.WorkItemType"
            "value" = $workItemType
        },
        @{
            "op" = "add"
            "path" = "/fields/System.Description"
            "value" = $description
        }
    )

    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    # Attempt to execute the POST request
    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers  -ContentType "application/json-patch+json" -Body $body
        return $response
    } catch {
        Write-Host "Request failed with the following details:"
        Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)"
        Write-Host "Status Description: $($_.Exception.Response.StatusDescription)"
        Write-Host "Body: $($jsonBody)"
        Write-Host "URI: $($uri)"
        
        # Check if the content can be converted to JSON
        try {
            $content = $_.Exception.Response.Content | ConvertFrom-Json
            Write-Host "Response Content: $($content)"
        } catch {
            Write-Host "Raw Response Content: $($_.Exception.Response.Content)"
        }
        
        return $null
    }
}



# Function to get all work items from the source project and area
function Get-WorkItems {
    $wiql = @{
        "query" = "SELECT [System.Id], [System.WorkItemType],[System.Title], [System.State], [System.AreaPath] , [System.Description] FROM WorkItems WHERE [System.AreaPath] = '$sourceArea'"
    }

    $uri = "$baseUri/$sourceProject/_apis/wit/wiql?api-version=6.0"
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($wiql | ConvertTo-Json -Compress)

    # Check if there are work items in the response and retrieve them
    if ($response -and $response.workItems) {
        $ids = $response.workItems.id -join ","
        $detailUri = "$baseUri/$sourceProject/_apis/wit/workitems?ids=$ids&`$expand=fields&api-version=6.0"
        $workItems = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
        return $workItems
    } else {
        Write-Host "No work items found."
        return @()  # Return an empty array if no work items are found
    }
}

# Main script execution
$workItems = Get-WorkItems
if ($workItems) {
    foreach ($wi in $workItems.value) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"

         # Attempt to create a new work item in the target project using the existing work item's details
        $newWorkItemResponse = Create-WorkItem $wi
        if ($newWorkItemResponse.id) {
            Write-Host "New work item created successfully with ID: $($newWorkItemResponse.id)"
        } else {
            Write-Host "Failed to create new work item. $($newWorkItemResponse)"
        }
    }
} else {
    Write-Host "No work items to process."
}




