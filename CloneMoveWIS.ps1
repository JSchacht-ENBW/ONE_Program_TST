# Set variables
$sourceOrg = "enbw"
$sourceProject = "ONE!"
$sourceArea = "ONE!\\xx_Sandkasten"  # Use double backslash in PowerShell for correct escaping
$targetOrg = "enbw"
$targetProject = "ONE! Program_Dev"
$PAT = "hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa"  # Securely pass your PAT

$AzureDevOpsPAT = 'hy5ljfnuzezpn5ojdasxtlhrfgopbpt3ezgrmaq5fqzsd7z4yfsa'
$AzureDevOpsAuthenicationHeader = @{
    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AzureDevOpsPAT"))
}

$OrganizationName = "enbw"
$UriOrganization = "https://dev.azure.com/$OrganizationName/"

#Lists all projects in your organization
$uriAccount = $UriOrganization + "_apis/projects?api-version=5.1"
Invoke-RestMethod -Uri $uriAccount -Method Get -Headers $AzureDevOpsAuthenicationHeader

# Headers for authentication
$headers = @{
    "Authorization" = "Basic $( [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PAT")) )"
}

# Function to create a work item in the target project
function Create-WorkItem($workItem) {
    $WorkItemType = $workItem.fields.'System.WorkItemType'
    $uri = $UriOrganization + $targetProject + "/_apis/wit/workitems/`$$WorkItemType?api-version=5.1"
    echo $uri

    # Define default values for required fields to ensure they are not null
    $title = if ($workItem.fields.'System.Title') { $workItem.fields.'System.Title' } else { "Default Title" }
    $state = if ($workItem.fields.'System.State') { $workItem.fields.'System.State' } else { "New" }
    $description = $workItem.fields.'System.Description'

    $body = @"
    [
        {
            "op": "add",
            "path": "/fields/System.Title",
            "value": "$title"
        },
        {
            "op": "add",
            "path": "/fields/System.State",
            "value": "$state"
        },
        {
            "op": "add",
            "path": "/fields/System.WorkItemType",
            "value": "$WorkItemType"
        },
        {
            "op": "add",
            "path": "/fields/System.Description",
            "value": "$description"
        }
    ]
"@ 

    # Attempt to execute the POST request
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $AzureDevOpsAuthenicationHeader -ContentType "application/json-patch+json" -Body $body
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
