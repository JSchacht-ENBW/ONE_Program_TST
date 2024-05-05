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
    # Description is escaped for JSON
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
            "path" = "/fields/System.Description"
            "value" = $workItem.fields.'System.Description' -replace '(["\\])', '\\$1'  # Escape special JSON characters in the description
        }
    )

    # Serialize the body using ConvertTo-Json with a depth to ensure all details are captured
    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    # Execute the PATCH request with the constructed JSON body
    $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $jsonBody
    return $response
}





