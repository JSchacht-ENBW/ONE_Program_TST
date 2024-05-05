# Set your Azure DevOps organization, project, and PAT
$Organization = "your-organization"
$Project = "your-project"
$PAT = "your-personal-access-token"

# Azure DevOps REST API endpoint for work items
$Uri = "https://dev.azure.com/$Organization/$Project/_apis/wit/workitems/3164029?api-version=6.0"

# Create headers for the request
$headers = @{
    "Authorization" = "Basic $PAT"
    "Content-Type" = "application/json-patch+json"
}

try {
    # Invoke REST API to retrieve work item details
    $response = Invoke-RestMethod -Uri $Uri -Method Get -Headers $headers

    # Process the response (you can customize this part)
    Write-Host "Work Item ID: $($response.id)"
    Write-Host "Title: $($response.fields.'System.Title')"
    Write-Host "Description: $($response.fields.'System.Description')"
}
catch {
    Write-Host "Error occurred: $($_.Exception.Message)"
}
