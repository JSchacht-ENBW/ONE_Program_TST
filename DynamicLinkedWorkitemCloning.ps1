# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceProjectID = "38def788-c6c3-414b-b0e3-b017687f4701"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$targetProjectID = "f7db8333-e29d-4dc4-8c52-cb0249449af2"
$targetArea = $targetProject
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa"  # Securely pass your PAT

# Base URI for Azure DevOps REST API calls
$baseUri = "https://dev.azure.com/$sourceOrg"
$identityuri  = "https://vssps.dev.azure.com/$sourceOrg/"

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
function Get-IdentityByDescriptor {
    param (
        [string]$descriptor,
        [hashtable]$headers,
        [string]$orgUrl
    )

    $identityUrl = "$orgUrl_apis/identities?descriptors=$descriptor&api-version=6.0"
    Write-Host "Identityurl:$identityUrl"
    try {
        $identity = Invoke-RestMethod -Uri $identityUrl -Method Get -Headers $headers
        return $identity
    } catch {
        Write-Host "No valid identity found for descriptor: $descriptor"
        return $null
    }
}

function Get-IdentityById {
    param (
        [string]$identityId,
        [hashtable]$headers,
        [string]$orgUrl
    )

    # Update the URL to use an endpoint appropriate for querying by identity ID
    $identityUrl = "$($identityuri)_apis/identities/$($identityId)?api-version=6.0"

    try {
        $identity = Invoke-RestMethod -Uri $identityUrl -Method Get -Headers $headers
        return $identity
    } catch {
        Write-Host "  No valid identity found for ID: $identityId"
        return $null
    }
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
        "System.ChangedDate", "System.ChangedBy", "System.RevisedDate", "Microsoft.VSTS.Common.ClosedDate","Microsoft.VSTS.Common.ActivatedDate",
        "System.AreaId", "System.IterationId", "System.WorkItemType", 
        "System.StateChangeDate", "System.AuthorizedDate", "System.PersonId",
        "System.BoardColumnDone", "System.Watermark" , "System.Parent" ,
         "System.BoardColumn","System.NodeName", "System.AuthorizedAs", "System.CommentCount"
         "Microsoft.VSTS.Common.StateChangeDate", "Microsoft.VSTS.Common.StackRank"
         "System.TeamProject", "System.AreaPath", "System.IterationPath" , "System.Reason"

    )

    $fieldNamesNotIncludes = @("Kanban.Column","System.IterationLevel","System.AreaLevel", "System.ExtensionMarker")

    $fieldNamesIndentity = @("System.AssignedTo","Microsoft.VSTS.Common.ActivatedBy","Microsoft.VSTS.Common.ClosedBy")

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
        $valueset = $false

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
            if ($field.Name -eq "System.State") {
                if ($value -eq "Closed") {
                $value = "Done"
                $valueset = $true}
            }
            # Handle identity fields
            if ($field.Name -in $fieldNamesIndentity) {
                $identityid = $($value.id)
                Write-Host "-------- Found identity id: $identityid"
                $identity = Get-IdentityByID -identityId $identityid -headers $headers -orgUrl $orgUrl
                if ($identity -and !$identity.inactive) {
                    $value = $identity
                    $valueset = $true
                } else {
                    Write-Host "-------- Invalid or inactive identity, skipping assignment for System.AssignedTo."
                    continue
                }
            }

            if ($valueset -eq $false) {
                $body += @{
                    "op"    = "add"
                    "path"  = "/fields/$($field.Name)"
                    "value" = $value
                }
            }
        }
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $AzureDevOpsAuthenicationHeader -ContentType "application/json-patch+json" -Body $jsonBody
        Write-Host "------ Successfully cloned new work item with ID: $($response.id)"
        Write-Host "........ Request Body: $jsonBody"
        return $response
    } catch {
        Write-Host "...... Failed to clone work item: $($_.Exception.Message)"
        Write-Host "........ Response:$response"
        Write-Host "........ mappedAreaPath:$mappedAreaPath"
        Write-Host "........ Target Project: $targetProject"
        Write-Host "........ Request Body: $jsonBody"
        Write-Host "........ URI: $uri"
       
        return $null
    }
}

function Get-WorkItemIdFromUrl {
    param ([string]$url)
    $pattern = '_apis/wit/workItems/(\d+)$'
    if ($url -match $pattern) {
        $workItemId = $matches[1]
        Write-Host "------ linked id $($workItemId) fround in $url"
        return [string]$workItemId  # Cast as string to ensure consistency
    } else {
        Write-Host "No valid work item ID found in the URL."
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
        Write-Host "  Failed to execute WIQL query: $($_.Exception.Message)"
        return $null
    }

    # Check if there are work items in the WIQL response and retrieve them
    if ($wiqlResponse -and $wiqlResponse.workItems) {
        $allWorkItems = @()
        foreach ($workItemRef in $wiqlResponse.workItems) {
            $processedItemCount++
            $workItemId = $workItemRef.id
            $detailUri = "$baseUri/$sourceProject/_apis/wit/workitems/$($workItemId)?api-version=6.0&`$expand=all"
            
            try {
                #$workItems = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
                $workItemDetails = Invoke-RestMethod -Uri $detailUri -Method Get -Headers $headers
                $allWorkItems += $workItemDetails
            } catch {
                Write-Host "...... Failed to retrieve details for work item ID $($workItemId): $($_.Exception.Message)"
                Write-Host "........ Status Code: $($_.Exception.Response.StatusCode.Value__)"
                Write-Host "........ Status Description: $($_.Exception.Response.StatusDescription)"
                Write-Host "........ Workitem: $($workItemId)"
                Write-Host "........ URI: $($detailUri)"
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

# Initialize counter for processed work items
$processedItemCount = 0

# Retrieve all work items details
Write-Host ""
Write-Host "-- "
Write-Host "-- START RETRIEVING SOURCE ITEMS "
$workItems = Get-AllWorkItemDetails -baseUri $baseUri -sourceProject $sourceProject -sourceArea $sourceArea -headers $headers
Write-Host "---- Retrieved $($workItems.count) work items from sourceProject $sourceProject sourceArea $sourceArea"

# Dictionary to map old IDs to new IDs
$idMapping = @{}

# Main script execution
# Main script execution
Write-Host "-- "
Write-Host "-- START CLONING SOURCE ITEMS "
if ($workItems) {
    foreach ($wi in $workItems) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "---- START CLONING SOURCE ITEM "
        Write-Host "------ Work Item ID: $($wi.id), WIT: $($wi.fields.'System.WorkItemType'), Title: $($wi.fields.'System.Title'), State: $($wi.fields.'System.State'), Description: $($wi.fields.'System.Description')"
        # Attempt to create a new work item in the target project using the existing work item's details
        $newWorkItemResponse = CloneWorkItem -orgUrl $UriOrganization -targetProject $targetProject -headers $headers -workItem $wi -areaPathMap $areaPathMap

        if ($newWorkItemResponse) {
            $newId = $newWorkItemResponse.id
            Write-Host "---- FINISHED CLONING SOURCE ITEM : $newId"
            $idMapping["$($wi.id)"] = $newId

            Write-Host "------ MAPPING : Old $($wi.id) to new $($idMapping[$wi.id]) ($($newId)) " 

            
        } else {
            Write-Host "------ Failed to create new work item. $($newWorkItemResponse)"
        }
        Write-Host "---- END CLONING SOURCE ITEM "
    }
} else {
    Write-Host "---- No work items to process."
}


# Function to update links between work items
function UpdateLink {
    param (
        [string]$orgUrl,
        [string]$targetProject,
        [hashtable]$headers,
        [int]$workItemId,
        [int]$linkedWorkItemId,
        [int]$linkedWorkItemIdOld,
        [string]$linkType,
        [int]$linkcount
    )
    $uri = "$orgUrl$targetProject/_apis/wit/workitems/$workItemId"
    $body = @()

    @linkvalue = @{
            "rel" = $linkType
            "url" = "$orgUrl$targetProject/_apis/wit/workitems/$linkedWorkItemId"
            "attributes" = @{
                "comment" = "Link cloned from old target $($oldtargetid) to new target $($linkedWorkItemId)"
            },
        "url" = "https://dev.azure.com/enbw/f7db8333-e29d-4dc4-8c52-cb0249449af2/_apis/wit/workitems/$workItemId"
    }

    $body += @{
        "op" = "add"
        "path" = "/relations/-"
        "value" = @linkvalue
    }
    
    
    $jsonBody = $body | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Patch -Headers $headers -ContentType "application/json-patch+json" -Body $jsonBody
        Write-Host "------Link updated successfully between $workItemId and $linkedWorkItemId"
    } catch {
        Write-Host "......Failed to update link: $($_.Exception.Message)"
        Write-Host "........ Response:$response"
        Write-Host "........ mappedAreaPath:$mappedAreaPath"
        Write-Host "........ Target Project: $targetProject"
        Write-Host "........ Request Body: $jsonBody"
        Write-Host "........ URI: $uri"
    }
}


# Convert hashtable to a dictionary with string keys
$stringKeyDictionary = [System.Collections.Generic.Dictionary[string,object]]::new()
foreach ($key in $idMapping.Keys) {
    $stringKeyDictionary.Add([string]$key, $idMapping[$key])
}

# Now convert this dictionary to JSON
$JsonIDmap = $stringKeyDictionary | ConvertTo-Json -Depth 10 -Compress
Write-Host "-- "
Write-Host "-- RETRIEVED ID MAP : $($JsonIDmap)"
Write-Host ""
Write-Host "-- "
Write-Host "-- START RELINKING CLONED RELATIONS"

if ($workItems) {
    foreach ($wi in $workItems) {
        # Print each work item's ID and Title (assuming ID is directly under the work item object)
        Write-Host "---- START RELINKING OLD WORKITEM $($wi.id)"
        $mappedids = $idMapping["$($wi.id)"]
        if ($mappedids) {
            Write-Host "------ Work Item ID: $($wi.id) has idmapping to $($mappedids)"
            # Now handle the cloning of links, adjusting them to point to the newly cloned work items
            if ($wi.relations) {
                $linkcount = 0
                foreach ($link in $wi.relations) {
                    $linkrel = $link.rel    
                    $linkcount++
                    Write-Host "link # : $linkcount"
                    $oldtargetid = WorkItemIdFromUrl -url $link.url
                    $newtargetid = $idMapping["$($oldtargetid)"] 
                    Write-Host "------ linkerelation:$linkrel to be transposed from $($oldtargetid) to $($newtargetid)"
                    # Extract the source item ID from the URL
                    if ($newtargetid) {  # This regex extracts the ID from the URL
                        Write-Host "------ Link changes for source and target $($mappedids) to  $($newtargetid)"
                        UpdateLink -orgUrl $UriOrganization -targetProject $targetProjectID -headers $headers -workItemId $mappedids -linkedWorkItemId $newtargetid -linkedWorkItemIdOld $($oldtargetid) -linkType $link.rel -linkcount $linkcount
                    }
                    else {
                            Write-Host "------ no new targetid for link $($mappedids) to  $($newtargetid)"
                    }
                }
            }
        } else {
            Write-Host "------ No ID mapping for original work item: $($wi.id)"
        }
    Write-Host "---- END RELINKING OLD WORKITEM $($wi.id)"
    }
} else {
    Write-Host "---- No work items to process."
}
Write-Host "-- "
Write-Host "-- END RELINKING CLONED RELATIONS"
   
