# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$targetArea = $targetProject
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


Write-Host "mappedAreaPath:$areamap"

function MapAreaPath {
    param (
        [string]$sourceAreaPath,
        [hashtable]$areaPathMap
    )

    # Check if the source AreaPath exists in the map
    if ($areaPathMap.ContainsKey($sourceAreaPath)) {
        return $areaPathMap[$sourceAreaPath]
    } else {
        # Return source if no mapping is found
        return $sourceAreaPath
    }
}

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


function CloneWorkItem {
    param (
        [string]$orgUrl,
        [string]$targetProject,
        [hashtable]$headers,
        [psobject]$workItem,
        [hashtable]$areaPathMap  # Pass the mapping for area paths
    )
    $WorkItemType = $workItem.fields.'System.WorkItemType'

    # Define non-writable fields
    $nonWritableFields = @(
        "System.Id", "System.Rev", "System.CreatedDate", "System.CreatedBy",
        "System.ChangedDate", "System.ChangedBy", "System.RevisedDate",
        "System.AreaId", "System.IterationId", "System.WorkItemType", 
        "System.StateChangeDate", "System.AuthorizedDate", "System.PersonId",
        "System.BoardColumnDone", "System.Watermark" , "System.Parent" ,
         "WEF_A6AE366B767347D78F18D7B9B9FEF8B5_System.ExtensionMarker" , "WEF_A6AE366B767347D78F18D7B9B9FEF8B5_Kanban.Column",
         "WEF_A6AE366B767347D78F18D7B9B9FEF8B5_Kanban.Column.Done",
         "System.BoardColumn",
         "Microsoft.VSTS.Common.StateChangeDate",
         "System.TeamProject", "System.AreaPath", "System.IterationPath"

    )

    $fieldNamesNotIncludes = @("Kanban.Column")

    $uri = $orgUrl  + $targetProject + "/_apis/wit/workitems/$" + $WorkItemType + "?api-version=5.1"
    $body = @()

    # AreaPath and IterationPath handling
    $body += @{
        "op"    = "add"
        "path"  = "/fields/System.AreaPath"
        "value" = $targetProject  # Adjust according to your logic or mappings
    }, @{
        "op"    = "add"
        "path"  = "/fields/System.IterationPath"
        "value" = $targetProject  # Adjust according to your logic or mappings
    }

    foreach ($field in $workItem.fields.PSObject.Properties.Name) {
        $includeField = $true

        # Check against non-writable fields list
        if ($field.Name -in $nonWritableFields) {
            $includeField = $false
        }

        # Check against field names that should not be included
        foreach ($excludeSubstring in $fieldNamesNotIncludes) {
            if ($field.Name.Contains($excludeSubstring)) {
                $includeField = $false
                break
            }
        }

        if ($includeField) {
            $body += @{
                "op"    = "add"
                "path"  = "/fields/$($field.Name)"
                "value" = $field.Value
            }
        }
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -ContentType "application/json-patch+json" -Body $body
        Write-Host "Successfully created new work item with ID: $($response.id)"
        return $response
    } catch {
        Write-Host "Failed to clone work item: $($_.Exception.Message)"
        Write-Host "Response:$response"
        Write-Host "mappedAreaPath:$mappedAreaPath"
        Write-Host "Target Project: $targetProject"
        Write-Host "Request Body: $jsonBody"
        Write-Host "URI: $uri"
        return $null
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

# Retrieve all work items details
$workItems = Get-AllWorkItemDetails -baseUri $baseUri -sourceProject $sourceProject -sourceArea $sourceArea -headers $headers

# Dictionary to map old IDs to new IDs
$idMapping = @{}

# Clone work items and store new IDs
foreach ($wi in $workItems) {
    $newId = CloneWorkItem -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -workItem $wi
    if ($newId) {
        $idMapping[$wi.id] = $newId
        Write-Host "Mapped old ID $($wi.id) to new ID $newId"
    }
}

# Adjust links to point to new IDs
foreach ($wi in $workItems) {
    if ($wi.relations -and $idMapping.ContainsKey($wi.id)) {
        foreach ($link in $wi.relations) {
            if ($idMapping.ContainsKey($link.attributes.id)) {
                # Here you would call a function to update the link to point to the new ID
                UpdateLink -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -oldId $wi.id -newId $idMapping[$wi.id] -newLinkedId $idMapping[$link.attributes.id]
            }
        }
    }
}
# Main script execution
#$workItems = Get-WorkItems
$workItems = $allDetails
if ($false) {
    foreach ($wi in $workItems) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"

         # Attempt to create a new work item in the target project using the existing work item's details
        #$newWorkItemResponse = Create-WorkItem $wi
        # Clone the work item
        if ($wi) {
            $newWorkItem = CloneWorkItem -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -workItem $wi -areaPathMap $areaPathMap
        }

        if ($newWorkItemResponse.id) {
            Write-Host "New work item created successfully with ID: $($newWorkItemResponse.id)"
        } else {
            Write-Host "Failed to create new work item. $($newWorkItemResponse)"
        }
    }
} 

