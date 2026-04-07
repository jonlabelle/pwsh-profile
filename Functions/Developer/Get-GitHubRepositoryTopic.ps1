function Get-GitHubRepositoryTopic
{
    <#
    .SYNOPSIS
        Gets GitHub repository topics from an explicit repository or the current Git repository.

    .DESCRIPTION
        Retrieves the current topic list for a GitHub repository.

        The target repository can be provided explicitly through -Repository or omitted to use the
        current Git repository's origin remote.

        Use -Name to filter the returned topics to one or more specific topic names. Topic filters
        are trimmed, lowercased, and de-duplicated before matching. Missing requested topics are
        reported in the result object instead of causing the command to fail.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to the REST API otherwise.

    .PARAMETER Name
        Optional repository topic name or names to match.

        When omitted, all topics are returned.

        Topic names are normalized before matching:
        - Leading and trailing whitespace is removed
        - Names are lowercased
        - Duplicate names are removed

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When omitted, the function tries to resolve the current Git repository's origin remote. If
        that cannot be determined, specify -Repository explicitly.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER Token
        Optional GitHub personal access token as a SecureString.

        If supplied, the token is used only for the outbound `gh` or REST request and is never
        written to command output.

        When omitted, the function checks the environment variable named by
        -TokenEnvironmentVariableName. If the GitHub CLI is installed, its existing authenticated
        session can also be used when no token is supplied. If `gh` is not available and the
        function falls back to REST, a token or token environment variable is required.

    .PARAMETER TokenEnvironmentVariableName
        The environment variable name to check for a GitHub token when -Token is not supplied.

        Defaults to GH_TOKEN.

        This environment variable is read only when -Token is not supplied. It is used for `gh`
        authentication and REST fallback.

    .EXAMPLE
        PS > Get-GitHubRepositoryTopic -Repository 'octo-org/service-api'

        Returns all topics for the specified repository.

    .EXAMPLE
        PS > Get-GitHubRepositoryTopic -Name 'powershell', 'automation'

        Returns matching topics from the current Git repository and reports any requested topics
        that are missing.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Get-GitHubRepositoryTopic -Repository 'octo-org/service-api' -Token $token

        Uses an explicit token to retrieve repository topics.

    .EXAMPLE
        PS > Get-GitHubRepositoryTopic -Repository 'octo-org/service-api' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.RepositoryTopics

        Returns the repository topic list, any requested filters, missing requested topics, and
        transport metadata.

    .NOTES
        Repository topics prefer the GitHub CLI-backed transport and fall back to direct REST API
        requests when necessary.

    .LINK
        https://docs.github.com/rest/repos/repos#get-all-repository-topics

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Get-GitHubRepositoryTopic.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [String[]]$Name,

        [Parameter()]
        [String]$Repository,

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
    $requestedTopics = @()
    $requestedTopicDisplay = 'all topics'

    $topicContext = & $helpers.GetRepositoryTopicsContext -Repository $Repository
    $transport = & $helpers.ResolveTransport

    try
    {
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $requestedTopics = @(& $helpers.NormalizeTopicNames -Names $Name)
            $requestedTopicDisplay = $requestedTopics -join ', '
        }

        $authContext = & $helpers.ResolveAuthContext `
            -Token $Token `
            -TokenEnvironmentVariableName $TokenEnvironmentVariableName `
            -RequireToken:($transport.Name -ne 'GhCli')

        $resource = & $helpers.TryGetGitHubResource `
            -Path $topicContext.CollectionPath `
            -BaseUri $topicContext.ApiBaseUri `
            -Transport $transport `
            -AuthContext $authContext `
            -MaxRetryCount $maxRetryCount `
            -InitialRetryDelaySeconds $initialRetryDelaySeconds `
            -Activity "Get repository topics for $($topicContext.RepositoryContext.NameWithOwner)"

        if (-not $resource.Found)
        {
            throw "GitHub repository topics were not found for $($topicContext.DisplayTarget)."
        }

        $allTopics = @(& $helpers.NormalizeTopicNames -Names @($resource.Resource.names))
        $matchedTopics = if ($requestedTopics.Count -gt 0)
        {
            @($allTopics | Where-Object { $_ -in $requestedTopics })
        }
        else
        {
            $allTopics
        }

        $missingTopics = if ($requestedTopics.Count -gt 0)
        {
            @($requestedTopics | Where-Object { $_ -notin $allTopics })
        }
        else
        {
            @()
        }

        return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopics' -Properties @{
            Repository = $topicContext.RepositoryContext.GhRepository
            Target = $topicContext.DisplayTarget
            Topics = $matchedTopics
            AllTopics = $allTopics
            RequestedTopics = $requestedTopics
            MissingTopics = $missingTopics
            TopicCount = $matchedTopics.Count
            TotalTopicCount = $allTopics.Count
            Transport = $transport.Name
            Authentication = $authContext.Source
        }
    }
    catch
    {
        $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
            -Operation 'get repository topics' `
            -Name $requestedTopicDisplay `
            -Target $topicContext.DisplayTarget `
            -Exception $_.Exception

        throw $friendlyMessage
    }
}
