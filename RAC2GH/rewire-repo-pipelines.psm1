function AppendSummary 
{
  [CmdletBinding()]
  param(
    [parameter(ValueFromPipeline)]
    $Text
  )

  process 
  {
    if($env:GITHUB_STEP_SUMMARY)
    {
        Write-Output $Text >> $env:GITHUB_STEP_SUMMARY
    }
  }
}

function CreateRepoPipelineRewireScript
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$TargetFile,

        [Parameter(Mandatory)]
        [string]$AzureOrganization,

        [Parameter(Mandatory)]
        [string]$AzureProject,
        
        [Parameter()]
        [string]$AzureRepo,

        [Parameter()]
        [string]$ServiceConnectionName,

        [Parameter()]
        [string]$BitbucketWorkspace,

        [Parameter()]
        [string]$BitbucketRepo,

        [Parameter(Mandatory)]
        [string]$GitHubOrganization,
        
        [Parameter(Mandatory)]
        [string]$GitHubRepository,

        [Parameter(Mandatory)]
        [string]$DefaultBranch
    )

    $AzureOrgUrl="https://dev.azure.com/$AzureOrganization"
 
    if($BitbucketRepo) 
    {
        $sourceRepoLabel="$BitbucketWorkspace/$BitbucketRepository"
        $pipelines = az pipelines list --org $AzureOrgUrl --project $AzureProject --repository-type Bitbucket --repository $BitbucketWorkspace/$BitbucketRepo `
            | jq -c | ConvertFrom-Json
    }
    else
    {
        $sourceRepoLabel="$AzureProject/$AzureRepository"
        $pipelines = az pipelines list --org $AzureOrgUrl --project $AzureProject --repository $AzureRepo `
            | jq -c | ConvertFrom-Json
    }

    Write-Host "Creating migration script for $sourceRepoLabel to GitHub $GitHubOrganization/$GitHubRepository"

    # Get all GitHub service connections
    $serviceEndpoints = az devops service-endpoint list --org $AzureOrgUrl --project $AzureProject --query "[?contains(@.url, 'github')]" | ConvertFrom-Json
    $serviceConnectionId = $null
    $serviceEndpoint = $null

    if($ServiceConnectionName)
    {
        # If a specific service connection was named we'll use that
        $serviceEndpoint = $serviceEndpoints | Where-Object { $_.name -eq $ServiceConnectionName } | Select-Object -First 1
        Write-Host "Using specified GitHub service connection $($serviceEndpoint.name) with id $($serviceEndpoint.id)"

        if($null -eq $serviceEndpoint)
        {
            throw "Could not find GitHub service connection named $ServiceConnectionName in $AzureOrgUrl/$AzureProject"
        }
    }
    else
    {
        # Otherwise default to the first one
        $serviceEndpoint = $serviceEndpoints | Select-Object -First 1
        Write-Host "Defaulting to GitHub service connection $($serviceEndpoint.name) with id $($serviceEndpoint.id)"
    }
        
    if($null -eq $serviceEndpoint)
    {
        throw "Could not find any suitable GitHub service connection in project $AzureProject within $AzureOrgUrl. Please ask an admin to add a GitHub service connection to your Azure Project. Ideally with the name `"racwa`"."
    }

    Add-Content -Path $TargetFile "# Auto generated Azure repo post-migration script for project $AzureProject within $AzureOrgUrl to GitHub project $GitHubOrganization/$GitHubRepository
#
# Please refer to the step by step documentation on confluence: https://rac-wa.atlassian.net/wiki/spaces/DEVX/pages/2829353121/Migrate+Azure+Pipelines
#
# Step 1:
#    Confirm the service connection is correct.
#    Confirm every RewirePipeline call in this file has the expected arguments
#
# Step 2:
#   Download the jq command line tool and add it to your path. You can install this with choco (choco install jq)
#
# Step 3:
#    Generate the Azure personal access token with scopes: Build (Read & execute); Release (Read)
#
# Step 4:
#    Open a new terminal/powershell instance. Assign the AzurePAT environment var, e.g. `$env:AzurePAT=<my_pat>
#
# Step 5:
#    Change the execution polity to allow to run the downloaded powershell script.
#    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
#
# Step 6:
#    Run the powershell script in your terminal/powershell instance!
#    Be sure to close the powershell process once you are finished.

# Ensure the AzurePAT env var has been assigned if not provided as a parameter"

    Add-Content -Path $TargetFile 'if(-not $(Test-Path env:\AzurePAT))
{
    throw "Please ensure the AzurePAT env var has been set"
}'

    # Append the required function
    Add-Content $TargetFile "`n# ====================== Rewire Pipeline Function Start ======================n# Skip this section"
    Get-Content .\rewire-pipeline-function.ps1 | Add-Content $TargetFile
    Add-Content $TargetFile "`n`n# ====================== Rewire Pipelines ======================n`n# Please verify the arguments supplied are correct`n"

    $serviceConnectionId = $serviceEndpoint.id
    Write-Host "Using connection endpoint: $($serviceEndpoint.name) with id $serviceConnectionId"

    Add-Content -Path $TargetFile "
# Using service connection: $($serviceEndpoint.name) with id $serviceConnectionId
`$serviceConnectionId=`"$serviceConnectionId`"
"

    # If there are more than 1 GH service connection then we'll add the others
    # as commented out lines. This way it should be easy to swap between them without having to rerun the workflow.
    # This may be necessary if the default service connection fails (auth or PAT expired/out of date)
    foreach($sc in $serviceEndpoints)
    {
        Write-Output "Discovered $($sc.type) service connection $($sc.name) with id $($sc.id)" >> $env:GITHUB_STEP_SUMMARY
    
        if($sc.id -eq $serviceConnectionId)
        {
            Write-Output "Defaulting to this service connection" >> $env:GITHUB_STEP_SUMMARY
        }
        else
        {
            Add-Content -Path $TargetFile "# Uncomment to use service connection: $($sc.name) with id $($sc.id)"
            Add-Content -Path $TargetFile "# `$serviceConnectionId=""$($sc.id)"""
            Add-Content -Path $TargetFile ""
        }
    }

    Write-Output "Located $($pipelines.count) pipelines"
    Write-Output "## Pipelines" >> $env:GITHUB_STEP_SUMMARY
    
    AppendSummary "Discovered $($pipelines.Count) pipelines in $sourceRepoName`n"

    foreach ($pipeline in $pipelines) 
    {
        $pipelineUrl = "$AzureOrgUrl/$AzureProject/_build?definitionId=$($pipeline.id)"
        $pipeline.path = $pipeline.path.TrimStart("\")
        $pipeline | Add-Member -MemberType NoteProperty -Name 'fullPath' -Value $($pipeline.path +"\" + $pipeline.name)
        Write-Host "Pipeline URL: $pipelineUrl"
        Write-Host "Pipeline Full Path: $($pipeline.fullPath)"
        
        AppendSummary "### Pipeline $($pipeline.fullPath)"
        AppendSummary "Name: $($pipeline.name)"
        AppendSummary "Path: $($pipeline.path)"
        AppendSummary "ID: $($pipeline.id)"
        AppendSummary "URL: $pipelineUrl`n"
        
        $migrateCommand = "RewirePipeline -AzureOrganization $AzureOrganization -AzureProject $AzureProject -GitHubOrganization $GitHubOrganization -GitHubRepository $GitHubRepository -DefaultBranch $DefaultBranch -PipelineId $($pipeline.id) -ServiceConnectionId `$serviceConnectionId -DryRun"
        
        Add-Content -Path $TargetFile "
# === Pipeline $($pipeline.fullPath). URL: $pipelineUrl"

        Add-Content -Path $TargetFile $migrateCommand
    }
}

Export-ModuleMember -Function CreateRepoPipelineRewireScript
