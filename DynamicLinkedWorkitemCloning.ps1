# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa"  # Securely pass your PAT

# Base URI for Azure DevOps REST API calls
$baseUri = "https://dev.azure.com/$sourceOrg"

$AzureDevOpsPAT = 'hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa'
$AzureDevOpsAuthenicationHeader = @{
    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AzureDevOpsPAT"))
}

$OrganizationName = "enbw"
$UriOrganization = "https://dev.azure.com/$OrganizationName/"

#Lists all projects in your organization
$uriAccount = $UriOrganization + "_apis/projects?api-version=5.1"
Invoke-RestMethod -Uri $uriAccount -Method Get -Headers $AzureDevOpsAuthenicationHeader

function Escape-JsonString {
    param (
        [string]$inputString
    )

    # Replace backslashes and double quotes for JSON
    $escapedString = $inputString -replace '\\', '\\\\' -replace '"', '\"'

    # If needed, add further replacements here for other special characters
    # These are not typical for JSON but may be needed for other parts of your application
    $escapedString =  $escapedString -replace '!', '' -replace '@', '' 

    return $escapedString
}


# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    $WorkItemType = $workItem.fields.'System.WorkItemType'
    #$WorkItemType = "Feature"

    $uri = $UriOrganization + $targetProject + "/_apis/wit/workitems/$" + $WorkItemType + "?api-version=5.1"
    echo $uri

    # Define default values for required fields to ensure they are not null
    $WorkItemTitle = if ($workItem.fields.'System.Title') { $workItem.fields.'System.Title' } else { "Default Title" }
    $WorkItemTitle = Escape-JsonString -inputString $WorkItemTitle
    $state = if ($workItem.fields.'System.State') { $workItem.fields.'System.State' } else { "New" }
    #$description = $workItem.fields.'System.Description'

    $body="[
    {
        `"op`": `"add`",
        `"path`": `"/fields/System.Title`",
        `"value`": `"$($WorkItemTitle)`"
    }
    ]"


    # Headers for authentication
    $headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AzureDevOpsPAT"))
        ContentType = "application/json-patch+json"
    }



    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -ContentType "application/json-patch+json" -Body $body
        Write-Host "Work item created successfully: $($response.id)"
        return $response
    } catch {
        Write-Host "Request failed with the following details:"
        Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)"
        Write-Host "Status Description: $($_.Exception.Response.StatusDescription)"
        Write-Host "Body: $body"
        Write-Host "URI: $uri"

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

function CloneWorkItem {
    param (
        [string]$orgUrl,
        [string]$projectId,
        [hashtable]$headers,
        [psobject]$sourceWorkItem
    )

    $uri = "$orgUrl/$projectId/_apis/wit/workitems/`$task?api-version=6.0"
    $body = @()

    # Loop through all fields in the source work item and prepare them for the new work item
    foreach ($field in $sourceWorkItem.fields.PSObject.Properties) {
        $body += @{
            "op" = "add"
            "path" = "/fields/$($field.Name)"
            "value" = $field.Value
        }
    }

    # Include relationships if necessary
    if ($sourceWorkItem.relations) {
        foreach ($link in $sourceWorkItem.relations) {
            $body += @{
                "op" = "add"
                "path" = "/relations/-"
                "value" = @{
                    "rel" = $link.rel
                    "url" = $link.url
                    "attributes" = @{
                        "comment" = "Cloned from work item $($sourceWorkItem.id)"
                    }
                }
            }
        }
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -Body $jsonBody -ContentType "application/json-patch+json"
        Write-Host "Successfully created new work item with ID: $($response.id)"
        return $response
    } catch {
        Write-Host "Failed to clone work item: $($_.Exception.Message)"
        Write-Host "Request Body: $jsonBody"
        return $null
    }
}


# Function to get all work items from the source project and area
function Get-WorkItems {
    $wiql = @{
        "query" = "SELECT [System.Id], [System.WorkItemType],[System.Title], [System.State], [System.AreaPath] , [System.Description] FROM WorkItems WHERE [System.AreaPath] = '$sourceArea'"
    }

    # Headers for authentication
    $headers = @{
        "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
        "Content-Type" = "application/json"
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

function Get-AllWorkItemDetails {
    param (
        [string]$baseUri,
        [string]$sourceProject,
        [string]$sourceArea,
        [hashtable]$headers
    )

    # WIQL query to retrieve work item IDs
    $wiql = @{
        "query" = "SELECT [System.Id] FROM WorkItems WHERE [System.AreaPath] = '$sourceArea'"
    }

    $uriWIQL = "$baseUri/$sourceProject/_apis/wit/wiql?api-version=6.0"
    
    # Execute the WIQL query
    try {
        $wiqlResponse = Invoke-RestMethod -Uri $uriWIQL -Method Post -Headers $headers -Body ($wiql | ConvertTo-Json -Compress)
    } catch {
        Write-Host "Failed to execute WIQL query: $($_.Exception.Message)"
        return $null
    }

    # Check if there are work items in the WIQL response and retrieve them
    if ($wiqlResponse -and $wiqlResponse.workItems) {
        $allWorkItems = @()
        foreach ($workItemRef in $wiqlResponse.workItems) {
            $workItemId = $workItemRef.id
            $detailUri = "$baseUri/$sourceProject/_apis/wit/workitems/$($workItemId)?api-version=6.0&`$expand=all"
            
            try {
                #$workItems = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
                $workItemDetails = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
                $allWorkItems += $workItemDetails
            } catch {
                Write-Host "Failed to retrieve details for work item ID $($workItemId): $($_.Exception.Message)"
                Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)"
                Write-Host "Status Description: $($_.Exception.Response.StatusDescription)"
                Write-Host "Workitem: $($workItemId)"
                Write-Host "URI: $($detailUri)"
            }
        }
        return $allWorkItems
    } else {
        Write-Host "No work items found."
        return @()
    }
}

# Headers for authentication
$headers = @{
    "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
    "Content-Type" = "application/json"
}

$allDetails = Get-AllWorkItemDetails -baseUri $baseUri -sourceProject $sourceProject -sourceArea $sourceArea -headers $headers

foreach ($item in $allDetails) {
    Write-Host "Detailed  Work Item ID: $($item.id), Title: $($item.fields.'System.Title')"
}

# Main script execution
#$workItems = Get-WorkItems
$workItems = $allDetails
if ($workItems) {
    foreach ($wi in $workItems) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"

         # Attempt to create a new work item in the target project using the existing work item's details
        #$newWorkItemResponse = Create-WorkItem $wi
        # Clone the work item
        if ($wi) {
            $newWorkItem = CloneWorkItem -orgUrl $organizationUrl -projectId $projectId -headers $headers -sourceWorkItem $sourceWorkItem
        }

        if ($newWorkItemResponse.id) {
            Write-Host "New work item created successfully with ID: $($newWorkItemResponse.id)"
        } else {
            Write-Host "Failed to create new work item. $($newWorkItemResponse)"
        }
    }
} else {
    Write-Host "No work items to process."
}

