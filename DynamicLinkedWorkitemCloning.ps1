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

function Encode-Html {
    param (
        [string]$HtmlContent
    )

    # Using .NET WebUtility class to HTML encode the content
    return [System.Net.WebUtility]::HtmlEncode($HtmlContent)
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
         "System.BoardColumn","System.NodeName", "System.AuthorizedAs", "System.CommentCount"
         "Microsoft.VSTS.Common.StateChangeDate", "Microsoft.VSTS.Common.StackRank"
         "System.TeamProject", "System.AreaPath", "System.IterationPath"

    )

    $fieldNamesNotIncludes = @("Kanban.Column","System.IterationLevel","System.AreaLevel", "System.ExtensionMarker")

    $uri = $orgUrl  + $targetProject + "/_apis/wit/workitems/$" + $WorkItemType + "?api-version=6.0"
    $body = @()

    # Prepare body with mapped AreaPath
    $body += @{
        "op"    = "add"
        "path"  = "/fields/System.AreaPath"
        "value" = $targetProject
    }
       $body += @{
        "op"    = "add"
        "path"  = "/fields/System.IterationPath"
        "value" = $targetProject
    }

    foreach ($field in  $workItem.fields.PSObject.Properties) {
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
            $value = $field.Value

            # Check if the field is the Description or any other field that may contain HTML
            if ($field.Name -eq "System.Description") {
                $value = Encode-Html -HtmlContent $value
            }

            # Check if the field is the Description or any other field that may contain HTML
            if ($field.Name -eq "System.State") {
                if ($value -eq "Closed") {
                $value = "Done"}
            }

            $body += @{
                "op"    = "add"
                "path"  = "/fields/$($field.Name)"
                "value" = $value
            }
        }
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -ContentType "application/json-patch+json" -Body $jsonBody
        Write-Host "Successfully cloned new work item with ID: $($response.id)"
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

# Retrieve all work items details
$workItems = Get-AllWorkItemDetails -baseUri $baseUri -sourceProject $sourceProject -sourceArea $sourceArea -headers $headers

foreach ($item in $allDetails) {
    Write-Host "Detailed  Work Item ID: $($item.id), Title: $($item.fields.'System.Title'), AreaPath: $($item.fields.'System.AreaPath')"
}

# Dictionary to map old IDs to new IDs
$idMapping = @{}

# Main script execution
# Main script execution
if ($workItems) {
    foreach ($wi in $workItems) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"

        # Attempt to create a new work item in the target project using the existing work item's details
        $newWorkItemResponse = CloneWorkItem -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -workItem $wi -areaPathMap $areaPathMap

        if ($newWorkItemResponse) {
            $newId = $newWorkItemResponse.id
            Write-Host "New work item found with ID: $newId"
            $idMapping[$wi.id] = $newId

            # Now handle the cloning of links, adjusting them to point to the newly cloned work items
            if ($wi.relations) {
                # Extract the source item ID from the URL
                if ($link.url -match '_apis/wit/workItems/(\d+)$') {  # This regex extracts the ID from the URL
                    $linkedWorkItemId = $Matches[1]

                    # Compare extracted ID with the current work item ID
                    if ($linkedWorkItemId -eq $wi.id) {
                        Write-Host "Link refers back to the same work item."
                    } else {
                        Write-Host "Link refers to a different work item with ID: $linkedWorkItemId"
                    }

                    # Check if the link's target work item ID is in the idMapping table
                    if ($idMapping.ContainsKey($linkedWorkItemId)) {
                        # Update the link to point to the new cloned work item ID
                        $newLinkedId = $idMapping[$linkedWorkItemId]
                        UpdateLink -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -workItemId $newId -linkedWorkItemId $newLinkedId -linkType $link.rel
                    }
                }
            }
        } else {
            Write-Host "Failed to create new work item. $($newWorkItemResponse)"
        }
    }
} else {
    Write-Host "No work items to process."
}

# Function to update links between work items
function UpdateLink {
    param (
        [string]$orgUrl,
        [string]$targetProject,
        [hashtable]$headers,
        [int]$workItemId,
        [int]$linkedWorkItemId,
        [string]$linkType
    )
    $uri = "$orgUrl/$targetProject/_apis/wit/workitems/$workItemId"
    $body = @{
        "op" = "add"
        "path" = "/relations/-"
        "value" = @{
            "rel" = $linkType
            "url" = "$orgUrl/$targetProject/_apis/wit/workitems/$linkedWorkItemId"
            "attributes" = @{
                "comment" = "Link cloned to new work item"
            }
        }
    }

    $jsonBody = ConvertTo-Json -Depth 5 -InputObject $body
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -ContentType "application/json-patch+json" -Body $jsonBody
        Write-Host "Link updated successfully between $workItemId and $linkedWorkItemId"
    } catch {
        Write-Host "Failed to update link: $($_.Exception.Message)"
    }
}
