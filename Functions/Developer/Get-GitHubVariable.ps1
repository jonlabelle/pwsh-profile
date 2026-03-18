function Get-GitHubVariable
{
    <#
    .SYNOPSIS
        Retrieves a GitHub variable from repository, environment, or organization scope.

    .DESCRIPTION
        Retrieves the current value and metadata for a GitHub variable from repository, environment,
        or organization scope.

        The function uses the GitHub CLI-backed API transport when available and falls back to the
        REST API otherwise.

    .PARAMETER Name
        The GitHub variable name to retrieve.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When omitted for repository and environment scopes, the current Git repository origin is used.

    .PARAMETER Environment
        The deployment environment name for environment variables.

        This parameter is only valid for environment-scoped variables and requires -Repository.

    .PARAMETER Organization
        The target organization for organization variables.

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

    .EXAMPLE
        PS > Get-GitHubVariable -Name 'DOTNET_VERSION' -Repository 'octo-org/service-api'

        Retrieves a repository variable.

    .EXAMPLE
        PS > Get-GitHubVariable -Name 'DEPLOY_RING' -Repository 'octo-org/service-api' -Environment 'Production'

        Retrieves an environment variable.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Get-GitHubVariable -Name 'REGION' -Organization 'octo-org' -Token $token

        Retrieves an organization variable by using an explicit token.

    .OUTPUTS
        GitHub.Variable

        Returns the variable name, value, visibility details, timestamps, and transport metadata.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Repository')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(ParameterSetName = 'Repository')]
        [Parameter(Mandatory, ParameterSetName = 'Environment')]
        [String]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'Environment')]
        [String]$Environment,

        [Parameter(Mandatory, ParameterSetName = 'Organization')]
        [ValidateNotNullOrEmpty()]
        [String]$Organization,

        [Parameter()]
        [SecureString]$Token,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TokenEnvironmentVariableName = 'GH_TOKEN'

    )

    function Import-GitHubConfigurationHelpersIfNeeded
    {
        if (-not (Get-Variable -Name 'PwshProfileGitHubConfigurationHelpers' -Scope Script -ErrorAction SilentlyContinue))
        {
            $dependencyDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
            $dependencyPath = Join-Path -Path $dependencyDirectory -ChildPath 'GitHubConfigurationHelpers.ps1'
            $dependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)

            if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf))
            {
                throw "Required dependency could not be found. Expected location: $dependencyPath"
            }

            try
            {
                . $dependencyPath
                Write-Verbose "Loaded GitHub configuration helpers from: $dependencyPath"
            }
            catch
            {
                throw "Failed to load GitHub configuration helpers from '$dependencyPath': $($_.Exception.Message)"
            }
        }
    }

    Import-GitHubConfigurationHelpersIfNeeded
    $helpers = $script:PwshProfileGitHubConfigurationHelpers
    $maxRetryCount = $helpers.DefaultRetryCount
    $initialRetryDelaySeconds = $helpers.DefaultInitialRetryDelaySeconds
    $variableContext = & $helpers.GetVariableContext `
        -ParameterSetName $PSCmdlet.ParameterSetName `
        -Repository $Repository `
        -Environment $Environment `
        -Organization $Organization

    $transport = & $helpers.ResolveTransport
    try
    {
        $authContext = & $helpers.ResolveAuthContext `
            -Token $Token `
            -TokenEnvironmentVariableName $TokenEnvironmentVariableName `
            -RequireToken:($transport.Name -ne 'GhCli')

        $variablePath = & $helpers.GetSingleItemPath -CollectionPath $variableContext.CollectionPath -Name $Name
        $resource = & $helpers.TryGetGitHubResource `
            -Path $variablePath `
            -BaseUri $variableContext.ApiBaseUri `
            -Transport $transport `
            -AuthContext $authContext `
            -MaxRetryCount $maxRetryCount `
            -InitialRetryDelaySeconds $initialRetryDelaySeconds `
            -Activity "Get GitHub variable $Name"

        if (-not $resource.Found)
        {
            throw "GitHub variable '$Name' was not found for $($variableContext.DisplayTarget)."
        }

        $rawResource = $resource.Resource
        $createdAt = if ($rawResource.PSObject.Properties['createdAt']) { $rawResource.createdAt } else { $rawResource.created_at }
        $updatedAt = if ($rawResource.PSObject.Properties['updatedAt']) { $rawResource.updatedAt } else { $rawResource.updated_at }
        $numSelectedRepos = if ($rawResource.PSObject.Properties['numSelectedRepos']) { $rawResource.numSelectedRepos } else { $rawResource.num_selected_repos }
        $selectedReposUrl = if ($rawResource.PSObject.Properties['selectedReposURL']) { $rawResource.selectedReposURL } else { $rawResource.selected_repositories_url }

        return & $helpers.NewOperationResult -TypeName 'GitHub.Variable' -Properties @{
            Name = $rawResource.name
            Value = $rawResource.value
            Scope = $variableContext.Scope
            Target = $variableContext.DisplayTarget
            Visibility = $rawResource.visibility
            CreatedAt = $createdAt
            UpdatedAt = $updatedAt
            NumSelectedRepos = $numSelectedRepos
            SelectedReposUrl = $selectedReposUrl
            Transport = $transport.Name
            Authentication = $authContext.Source
        }
    }
    catch
    {
        $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
            -Operation 'get variable' `
            -Name $Name `
            -Target $variableContext.DisplayTarget `
            -Exception $_.Exception

        throw $friendlyMessage
    }
}
