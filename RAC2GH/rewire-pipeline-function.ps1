function RewirePipeline 
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AzureOrganization,

        [Parameter(Mandatory)]
        [string]$AzureProject,

        [Parameter(Mandatory)]
        [string]$PipelineId,

        [Parameter(Mandatory)]
        [string]$GitHubOrganization,
        
        [Parameter(Mandatory)]
        [string]$GitHubRepository,

        [Parameter(Mandatory)]
        [string]$DefaultBranch,

        [Parameter(Mandatory)]
        [string]$ServiceConnectionId,

        [switch]
        [bool]$DryRun
    )

    if($false -eq $(Test-Path env:\AzurePAT))
    {
        throw "Please ensure the AzurePAT env var has been set"
    }

    $newData = @{
        repository = @{
            properties = @{
                apiUrl = "https://api.github.com/repos/$GitHubOrganization/$GitHubRepository";
                branchesUrl = "https://api.github.com/repos/$GitHubOrganization/$GitHubRepository/branches";
                cloneUrl = "https://github.com/$GitHubOrganization/$GitHubRepository.git";
                connectedServiceId = $ServiceConnectionId;
                defaultBranch = $DefaultBranch;
                fullName = "$GitHubOrganization/$GitHubRepository";
                manageUrl = "https://github.com/$GitHubOrganization/$GitHubRepository";
                orgName = $GitHubOrganization;
                refsUrl = "https://api.github.com/repos/$GitHubOrganization/$GitHubRepository/git/refs";
                safeRepository = "$GitHubOrganization/$GitHubRepository";
                shortName = $GitHubRepository;
                reportBuildStatus = "true";
            }
            id = "$GitHubOrganization/$GitHubRepository";
            type = "GitHub";
            name = "$GitHubOrganization/$GitHubRepository";
            url = "https://github.com/$GitHubOrganization/$GitHubRepository.git";
            defaultBranch = $DefaultBranch;
            # missing checkoutSubmodules and clean. We will insert original values later with jq
        }
    }

    # Use random prefix to prevent contamination from other pipelines
    $filePrefix = "$AzureOrganization-$AzureProject-$PipelineId-$(New-Guid)"
    
    $url = "https://dev.azure.com/$AzureOrganization/$AzureProject/_apis/build/definitions/$($PipelineId)?api-version=6.0";
    $autHeader = "Authorization: Basic $([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("pat:$($env:AzurePAT)")))"

    try
    {
        # Store data as json to pass into jq later
        ConvertTo-Json $newData | Out-File -FilePath "$filePrefix-newData.json"

        # Get the pipelines current state and store in file for later user with jq
        curl -s --location --request GET $url --header $autHeader `
            | jq `
            | Out-File -FilePath "$filePrefix-data.json"
        
        # Take original data, remove .repository, and add new data to the object. Then we add the original clean and checkoutSubmodules values
        $data = jq -c -n --argfile newData "$filePrefix-newData.json" --argfile data "$filePrefix-data.json" '$data | del(.repository) * $newData | .repository += {clean: $data.repository.clean, checkoutSubmodules: $data.repository.checkoutSubmodules}'
    }
    finally
    {
        Remove-Item "$filePrefix-data.json"
        Remove-Item "$filePrefix-newData.json"
    }

    Write-Output "New pipeline repository settings:"
    $data | jq '.repository' | ConvertFrom-Json | Write-Output

    if(-not $DryRun)
    {
        curl -s --location --request PUT $url --header $autHeader
    }
    else {
        Write-Output "Dry run mode enabled. No changes have been submitted"
    }
}
