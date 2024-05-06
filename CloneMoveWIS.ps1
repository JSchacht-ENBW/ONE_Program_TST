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
    "Content-Type" = "application/json"
}

# Function to create a work item in the target project
function Create-WorkItem($workItem) {


    $workItemType = $workItem.fields.'System.WorkItemType'
    $uri = "$baseUri/$targetProject/_apis/wit/workitems/`${{workItemType}}?validateOnly=False&bypassRules=True&suppressNotifications=True&$expand=fields&api-version=7.1"
   

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
            "value" = $workItem.fields.'System.WorkItemType'  # Set the description from the work item
        },
        @{
            "op" = "add"
            "path" = "/fields/System.Description"
            "value" = $workItem.fields.'System.Description'  # Set the description from the work item
        }
    )

    # Serialize the body using ConvertTo-Json with a depth to ensure all details are captured
    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    # Ensure necessary fields exist before proceeding
    if (-not $workItem.fields['System.Title'] -or -not $workItem.fields['System.WorkItemType']) {
        Write-Host "Necessary fields are missing from the work item."
        return $jsonBody
    }


    # Execute the PATCH request with the constructed JSON body
    $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $jsonBody
    return $response
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




