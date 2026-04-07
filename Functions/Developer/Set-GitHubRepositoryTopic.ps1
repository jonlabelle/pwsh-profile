function Set-GitHubRepositoryTopic
{
    <#
    .SYNOPSIS
        Ensures one or more GitHub repository topics are present.

    .DESCRIPTION
        Adds one or more topics to a GitHub repository without removing unrelated existing topics.

        Topic operations are idempotent:
        - Requested topics that already exist are left unchanged
        - Missing requested topics are added
        - Repeated calls with the same topic names return Unchanged

        The target repository can be provided explicitly through -Repository or omitted to use the
        current Git repository's origin remote.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to the REST API otherwise.

        The function supports:
        - One or many topic names through -Name
        - Topic normalization and de-duplication
        - -WhatIf/-Confirm through ShouldProcess
        - Secure PAT input via -Token with fallback to GH_TOKEN
        - Exponential backoff retries for transient failures

    .PARAMETER Name
        One or more repository topic names to ensure are present.

        Topic names are normalized before they are applied:
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
        PS > Set-GitHubRepositoryTopic -Name 'powershell' -Repository 'octo-org/service-api'

        Ensures the repository has the powershell topic.

    .EXAMPLE
        PS > Set-GitHubRepositoryTopic -Name 'powershell', 'automation'

        Ensures the current Git repository includes both topics while preserving unrelated topics.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Set-GitHubRepositoryTopic -Name 'internal-tooling' -Repository 'octo-org/service-api' -Token $token -WhatIf

        Shows what would happen without changing repository topics.

    .EXAMPLE
        PS > Set-GitHubRepositoryTopic -Name 'internal-tooling' -Repository 'octo-org/service-api' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.RepositoryTopicSetResult

        Returns a summary object with the requested topics, added topics, final topic list, and
        transport metadata.

    .NOTES
        Repository topics prefer the GitHub CLI-backed transport and fall back to direct REST API
        requests when necessary.

    .LINK
        https://docs.github.com/rest/repos/repos#replace-all-repository-topics

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Set-GitHubRepositoryTopic.ps1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [String[]]$Name,

        [Parameter()]
        [String]$Repository,

        [Parameter()]
        [SecureString]$Token,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$TokenEnvironmentVariableName = 'GH_TOKEN'
    )

    begin
    {
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
    }

    process
    {
        $requestedTopics = @(& $helpers.NormalizeTopicNames -Names $Name)
        if ($requestedTopics.Count -eq 0)
        {
            throw 'Provide at least one GitHub topic name.'
        }

        $topicContext = & $helpers.GetRepositoryTopicsContext -Repository $Repository
        $transport = & $helpers.ResolveTransport
        $authContext = & $helpers.ResolveAuthContext `
            -Token $Token `
            -TokenEnvironmentVariableName $TokenEnvironmentVariableName `
            -RequireToken:($transport.Name -ne 'GhCli')

        $requestedTopicDisplay = $requestedTopics -join ', '

        try
        {
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

            $existingTopics = @(& $helpers.NormalizeTopicNames -Names @($resource.Resource.names))
            $addedTopics = @($requestedTopics | Where-Object { $_ -notin $existingTopics })
            $finalTopics = @($existingTopics + $addedTopics)

            if ($addedTopics.Count -eq 0)
            {
                return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicSetResult' -Properties @{
                    Repository = $topicContext.RepositoryContext.GhRepository
                    Target = $topicContext.DisplayTarget
                    RequestedTopics = $requestedTopics
                    AddedTopics = @()
                    Topics = $existingTopics
                    Status = 'Unchanged'
                    Changed = $false
                    Transport = $transport.Name
                    Authentication = $authContext.Source
                    Message = "All requested repository topics are already present for $($topicContext.DisplayTarget)."
                }
            }

            if (-not $PSCmdlet.ShouldProcess("$($topicContext.DisplayTarget) :: $requestedTopicDisplay", 'Update GitHub repository topics'))
            {
                return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicSetResult' -Properties @{
                    Repository = $topicContext.RepositoryContext.GhRepository
                    Target = $topicContext.DisplayTarget
                    RequestedTopics = $requestedTopics
                    AddedTopics = $addedTopics
                    Topics = $finalTopics
                    Status = 'WhatIf'
                    Changed = $false
                    Transport = $transport.Name
                    Authentication = $authContext.Source
                    Message = 'Repository topic update skipped by WhatIf.'
                }
            }

            $response = & $helpers.InvokeGitHubRequest `
                -Method 'PUT' `
                -BaseUri $topicContext.ApiBaseUri `
                -Path $topicContext.CollectionPath `
                -Transport $transport `
                -AuthContext $authContext `
                -Body @{ names = $finalTopics } `
                -MaxRetryCount $maxRetryCount `
                -InitialRetryDelaySeconds $initialRetryDelaySeconds `
                -Activity "Update repository topics for $($topicContext.RepositoryContext.NameWithOwner)" `
                -SensitiveValues @()

            $resolvedTopics = if ($null -ne $response)
            {
                @(& $helpers.NormalizeTopicNames -Names @($response.names))
            }
            else
            {
                $finalTopics
            }

            return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicSetResult' -Properties @{
                Repository = $topicContext.RepositoryContext.GhRepository
                Target = $topicContext.DisplayTarget
                RequestedTopics = $requestedTopics
                AddedTopics = $addedTopics
                Topics = $resolvedTopics
                Status = 'Updated'
                Changed = $true
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Repository topics were updated for $($topicContext.DisplayTarget)."
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'set repository topics' `
                -Name $requestedTopicDisplay `
                -Target $topicContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
    }
}
