function Remove-GitHubRepositoryTopic
{
    <#
    .SYNOPSIS
        Ensures one or more GitHub repository topics are absent.

    .DESCRIPTION
        Removes one or more topics from a GitHub repository while preserving unrelated remaining
        topics.

        Topic operations are idempotent:
        - Requested topics that are already absent are left unchanged
        - Present requested topics are removed
        - Repeated calls with the same topic names return AlreadyAbsent once the topics are gone

        The target repository can be provided explicitly through -Repository or omitted to use the
        current Git repository's origin remote.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to the REST API otherwise.

    .PARAMETER Name
        One or more repository topic names to ensure are absent.

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
        PS > Remove-GitHubRepositoryTopic -Name 'deprecated' -Repository 'octo-org/service-api'

        Ensures the deprecated topic is removed from the repository.

    .EXAMPLE
        PS > Remove-GitHubRepositoryTopic -Name 'powershell', 'automation'

        Removes matching topics from the current Git repository while preserving unrelated topics.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Remove-GitHubRepositoryTopic -Name 'internal-only' -Repository 'octo-org/service-api' -Token $token -WhatIf

        Shows what would happen without changing repository topics.

    .EXAMPLE
        PS > Remove-GitHubRepositoryTopic -Name 'internal-only' -Repository 'octo-org/service-api' -TokenEnvironmentVariableName 'GITHUB_ADMIN_TOKEN'

        Reads the GitHub token from a non-default environment variable.

    .OUTPUTS
        GitHub.RepositoryTopicRemoveResult

        Returns a summary object with the requested topics, removed topics, final topic list, and
        transport metadata.

    .NOTES
        Repository topics prefer the GitHub CLI-backed transport and fall back to direct REST API
        requests when necessary.

    .LINK
        https://docs.github.com/rest/repos/repos#replace-all-repository-topics

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Remove-GitHubRepositoryTopic.ps1
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
            $removedTopics = @($requestedTopics | Where-Object { $_ -in $existingTopics })
            $finalTopics = @($existingTopics | Where-Object { $_ -notin $requestedTopics })

            if ($removedTopics.Count -eq 0)
            {
                return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicRemoveResult' -Properties @{
                    Repository = $topicContext.RepositoryContext.GhRepository
                    Target = $topicContext.DisplayTarget
                    RequestedTopics = $requestedTopics
                    RemovedTopics = @()
                    Topics = $existingTopics
                    Status = 'AlreadyAbsent'
                    Changed = $false
                    Transport = $transport.Name
                    Authentication = $authContext.Source
                    Message = "All requested repository topics are already absent for $($topicContext.DisplayTarget)."
                }
            }

            if (-not $PSCmdlet.ShouldProcess("$($topicContext.DisplayTarget) :: $requestedTopicDisplay", 'Update GitHub repository topics'))
            {
                return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicRemoveResult' -Properties @{
                    Repository = $topicContext.RepositoryContext.GhRepository
                    Target = $topicContext.DisplayTarget
                    RequestedTopics = $requestedTopics
                    RemovedTopics = $removedTopics
                    Topics = $finalTopics
                    Status = 'WhatIf'
                    Changed = $false
                    Transport = $transport.Name
                    Authentication = $authContext.Source
                    Message = 'Repository topic removal skipped by WhatIf.'
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

            return & $helpers.NewOperationResult -TypeName 'GitHub.RepositoryTopicRemoveResult' -Properties @{
                Repository = $topicContext.RepositoryContext.GhRepository
                Target = $topicContext.DisplayTarget
                RequestedTopics = $requestedTopics
                RemovedTopics = $removedTopics
                Topics = $resolvedTopics
                Status = 'Removed'
                Changed = $true
                Transport = $transport.Name
                Authentication = $authContext.Source
                Message = "Repository topics were updated for $($topicContext.DisplayTarget)."
            }
        }
        catch
        {
            $friendlyMessage = & $helpers.GetFriendlyErrorMessage `
                -Operation 'remove repository topics' `
                -Name $requestedTopicDisplay `
                -Target $topicContext.DisplayTarget `
                -Exception $_.Exception

            throw $friendlyMessage
        }
    }
}
