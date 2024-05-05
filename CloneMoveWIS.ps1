# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa"  # Securely pass your PAT

# Base URI for Azure DevOps REST API calls
$baseUri = "https://dev.azure.com/$sourceOrg"

# Headers for authentication
$headers = @{
    "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
    "Content-Type" = "application/json"
}

# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    # Check for each necessary field and gather missing field names if any
    $missingFields = @()
    if (-not $workItem.fields.'System.Title') { $missingFields += "System.Title" }
    if (-not $workItem.fields.'System.WorkItemType') { $missingFields += "System.WorkItemType" }
    if (-not $workItem.fields.'System.State') { $missingFields += "System.State" }
    if (-not $workItem.fields.'System.Description') { $missingFields += "System.Description" }

    # If there are any missing fields, report them and exit the function
    if ($missingFields.Count -gt 0) {
        Write-Host "Necessary fields are missing from the work item: $($missingFields -join ', ')"
        return $null
    }

    # Construct the URI for creating a new work item based on the type from the existing item
    $workItemType = $workItem.fields.'System.WorkItemType'
    $uri = "$baseUri/$targetProject/_apis/wit/workitems/`${$workItemType}?api-version=6.0"
    
    # Define the body as an array of hashtables, setting title, state, and description from the submitted work item
    $body = @(
        @{
            "op" = "add"
            "path" = "/fields/System.Title"
            "value" = $workItem.fields.'System.Title'  # Set the title from the work item
        },
        @{
            "op" = "add"
            "path" = "/fields/System.State"
            "value" = $workItem.fields.'System.State'  # Set the state from the work item
        },
        @{
            "op" = "add"
            "path" = "/fields/System.WorkItemType"
            "value" = $workItem.fields.'System.WorkItemType'  # Incorrectly set in the example, not usually set via PATCH
        },
        @{
            "op" = "add"
            "path" = "/fields/System.Description"
            "value" = $workItem.fields.'System.Description'  # Set the description from the work item
        }
    )

    # Serialize the body using ConvertTo-Json with a depth to ensure all details are captured
    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    # Execute the PATCH request with the constructed JSON body
    $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $jsonBody
    return $response
}


# Main script execution
$workItems = Get-WorkItems
if ($workItems) {
    foreach ($wi in $workItems.value) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"

         # Attempt to create a new work item in the target project using the existing work item's details
        $newWorkItemResponse = Create-WorkItem $wi
        if ($newWorkItemResponse) {
            Write-Host "New work item created successfully with ID: $($newWorkItemResponse.id)"
        } else {
            Write-Host "Failed to create new work item."
        }
    }
} else {
    Write-Host "No work items to process."
}





