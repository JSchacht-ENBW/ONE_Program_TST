# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\\\xx_Sandkasten"
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
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body ($wiql | ConvertTo-Json -Compress)
    Write-Host "Response: $($response | ConvertTo-Json -Compress)"

    if ($response -and $response.workItems) {
        $ids = $response.workItems.id -join ","
        $detailUri = "$baseUri/$sourceProject/_apis/wit/workitems?ids=$ids&`$expand=fields,relations&api-version=6.0"
        $workItems = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
        return $workItems
    } else {
        Write-Host "No work items found."
        return $null
    }
}


# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    # Ensure necessary fields exist before proceeding
    if (-not $workItem.fields['System.Title'] -or -not $workItem.fields['System.WorkItemType']) {
        Write-Host "Necessary fields are missing from the work item."
        return $null
    }

    $uri = "$baseUri/$targetProject/_apis/wit/workitems/`$$workItem.fields['System.WorkItemType']?api-version=6.0"
    
    # Define the body as an array of hashtables, modifying title and description
    $body = @(
        @{
            "op" = "add"
            "path" = "/fields/System.Title"
            "value" = "Cloned Title - originally from another project"
        },
        @{
            "op" = "add"
            "path" = "/fields/System.Description"
            "value" = "This is a cloned item from another project."
        }
        # Add more fields as necessary
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
    #foreach ($wi in $workItems) {
    #    $newWi = Create-WorkItem $wi
    #    Write-Host "Created new work item with ID: $($newWi.id)"
    Write-Host "Returned work items with ID: $($workItems)"
    }
} else {
    Write-Host "No work items to process."
}
