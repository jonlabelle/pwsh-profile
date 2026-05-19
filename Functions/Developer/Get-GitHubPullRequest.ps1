function Get-GitHubPullRequest
{
    <#
    .SYNOPSIS
        Retrieves GitHub pull requests for the current user or a specified GitHub scope.

    .DESCRIPTION
        Searches GitHub pull requests and returns matching results with repository, author, state,
        URL, and timestamp metadata.

        By default, the function retrieves open pull requests authored by the authenticated GitHub
        user. Use -Author to search pull requests authored by another user. Use -Organization,
        -Owner, or -Repository to narrow the search to a GitHub organization, repository owner, or
        repository.

        Current-user author filtering remains the default even when scope filters are supplied. Use
        -AllAuthors with -Organization, -Owner, or -Repository to return pull requests from every
        author in that scope.

        The function prefers the GitHub CLI-backed API transport when `gh` is available and falls
        back to the REST API otherwise. Results are retrieved page by page up to GitHub Search API
        limits.

    .PARAMETER State
        Pull request state to retrieve. Valid values are Open, Closed, Merged, and All.

        Defaults to Open.

        Closed returns closed pull requests that were not merged. Merged returns pull requests that
        were merged. All returns open, closed, and merged pull requests.

    .PARAMETER Author
        GitHub username whose pull requests should be returned.

        When omitted, the authenticated GitHub user is used by default. Use -AllAuthors with a scope
        filter to omit author filtering.

        The value @me is accepted and resolves to the authenticated GitHub user.

    .PARAMETER AllAuthors
        Returns pull requests from all authors in the specified -Organization, -Owner, or -Repository
        scope.

        This switch cannot be combined with -Author and requires at least one scope filter.

    .PARAMETER Organization
        GitHub organization whose repositories should be searched.

        Combine with -Author to find pull requests authored by a user within an organization, or use
        -AllAuthors to return pull requests from every author in the organization.

    .PARAMETER Owner
        GitHub user or organization account whose repositories should be searched.

        This uses GitHub's `user:` search qualifier and can be used for repositories owned by a
        personal account. Use -Organization for organization-specific searches.

    .PARAMETER Repository
        The target repository in OWNER/REPO or HOST/OWNER/REPO format.

        When supplied, the search is limited to that repository. HOST/OWNER/REPO can be used for
        GitHub Enterprise hosts.

        Examples:
        - octo-org/service-api
        - github.example.com/platform/service-api

    .PARAMETER GitHubHost
        GitHub host to query for user, owner, or organization searches.

        Defaults to github.com. Repository searches derive the host from -Repository unless
        -GitHubHost is explicitly supplied, in which case the values must agree.

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
        PS > Get-GitHubPullRequest

        Retrieves open pull requests authored by the authenticated GitHub user.

    .EXAMPLE
        PS > Get-GitHubPullRequest -State Merged

        Retrieves merged pull requests authored by the authenticated GitHub user.

    .EXAMPLE
        PS > Get-GitHubPullRequest -Author 'octocat' -State Closed

        Retrieves closed, unmerged pull requests authored by octocat.

    .EXAMPLE
        PS > Get-GitHubPullRequest -Organization 'octo-org' -AllAuthors -State All

        Retrieves open, closed, and merged pull requests in repositories owned by octo-org.

    .EXAMPLE
        PS > Get-GitHubPullRequest -Repository 'octo-org/service-api' -AllAuthors

        Retrieves open pull requests in the octo-org/service-api repository from every author.

    .EXAMPLE
        PS > $token = ConvertTo-SecureString $env:GITHUB_ADMIN_TOKEN -AsPlainText -Force
        PS > Get-GitHubPullRequest -Author 'octocat' -Owner 'octo-org' -Token $token

        Retrieves open pull requests authored by octocat in repositories owned by octo-org, using an
        explicit token.

    .OUTPUTS
        GitHub.PullRequestSearch

        Returns a search result object with matching pull requests, query metadata, transport
        details, and counts.

    .NOTES
        Pull request searches prefer the GitHub CLI-backed transport and fall back to direct REST API
        requests when necessary.

        GitHub Search API results are limited by GitHub's search result cap. The
        SearchResultLimitReached property indicates when GitHub reported more matches than were
        returned.

    .LINK
        https://docs.github.com/search-github/searching-on-github/searching-issues-and-pull-requests

    .LINK
        https://github.com/jonlabelle/pwsh-profile/blob/main/Functions/Developer/Get-GitHubPullRequest.ps1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Open', 'Closed', 'Merged', 'All')]
        [String]$State = 'Open',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Author,

        [Parameter()]
        [Switch]$AllAuthors,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Organization,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Owner,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Repository,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$GitHubHost = 'github.com',

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

    function Resolve-GitHubPullRequestSearchHost
    {
        param(
            [String]$RequestedHost,
            [PSCustomObject]$RepositoryContext,
            [Boolean]$GitHubHostWasSpecified
        )

        $normalizedRequestedHost = $RequestedHost.Trim()
        if ($normalizedRequestedHost -match '^https?://')
        {
            $normalizedRequestedHost = ([Uri]$normalizedRequestedHost).Host
        }

        if ($RepositoryContext)
        {
            if (
                $GitHubHostWasSpecified -and
                -not [string]::IsNullOrWhiteSpace($normalizedRequestedHost) -and
                $normalizedRequestedHost.ToLowerInvariant() -ne $RepositoryContext.Host.ToLowerInvariant()
            )
            {
                throw "Repository '$Repository' resolves to host '$($RepositoryContext.Host)', which does not match -GitHubHost '$RequestedHost'."
            }

            return [PSCustomObject]@{
                Host = $RepositoryContext.Host
                BaseUri = $RepositoryContext.ApiBaseUri
            }
        }

        return [PSCustomObject]@{
            Host = $normalizedRequestedHost
            BaseUri = (& $script:PwshProfileGitHubConfigurationHelpers.BuildGitHubApiBaseUri $normalizedRequestedHost)
        }
    }

    function Resolve-GitHubCurrentUserLogin
    {
        param(
            [String]$BaseUri,
            [PSCustomObject]$Transport,
            [PSCustomObject]$AuthContext,
            [Int]$MaxRetryCount,
            [Int]$InitialRetryDelaySeconds
        )

        $invokeGitHubRequestParams = @{
            Method = 'GET'
            BaseUri = $BaseUri
            Path = '/user'
            Transport = $Transport
            AuthContext = $AuthContext
            Body = $null
            MaxRetryCount = $MaxRetryCount
            InitialRetryDelaySeconds = $InitialRetryDelaySeconds
            Activity = 'Resolve authenticated GitHub user'
        }
        $user = & $script:PwshProfileGitHubConfigurationHelpers.InvokeGitHubRequest @invokeGitHubRequestParams

        if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.login))
        {
            throw 'Unable to determine the authenticated GitHub user.'
        }

        return [string]$user.login
    }

    function Get-GitHubPullRequestRepositoryName
    {
        param([String]$RepositoryUrl)

        if ([string]::IsNullOrWhiteSpace($RepositoryUrl))
        {
            return $null
        }

        if ($RepositoryUrl -match '/repos/(?<owner>[^/]+)/(?<repo>[^/]+)$')
        {
            return "$($matches['owner'])/$($matches['repo'])"
        }

        return $null
    }

    function ConvertTo-GitHubPullRequestResult
    {
        param([PSCustomObject]$Item)

        $repositoryName = Get-GitHubPullRequestRepositoryName -RepositoryUrl $Item.repository_url
        $mergedAt = if ($Item.pull_request) { $Item.pull_request.merged_at } else { $null }
        $isMerged = -not [string]::IsNullOrWhiteSpace([string]$mergedAt)
        $labels = @($Item.labels | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $result = [PSCustomObject]@{
            Repository = $repositoryName
            Number = $Item.number
            Title = $Item.title
            State = $Item.state
            IsMerged = $isMerged
            IsDraft = [bool]$Item.draft
            Author = $Item.user.login
            Url = $Item.html_url
            ApiUrl = if ($Item.pull_request) { $Item.pull_request.url } else { $null }
            Labels = $labels
            Comments = $Item.comments
            CreatedAt = $Item.created_at
            UpdatedAt = $Item.updated_at
            ClosedAt = $Item.closed_at
            MergedAt = $mergedAt
        }
        $result.PSObject.TypeNames.Insert(0, 'GitHub.PullRequest')

        return $result
    }

    Import-GitHubConfigurationHelpersIfNeeded
    $helpers = $script:PwshProfileGitHubConfigurationHelpers
    $maxRetryCount = $helpers.DefaultRetryCount
    $initialRetryDelaySeconds = $helpers.DefaultInitialRetryDelaySeconds

    if ($PSBoundParameters.ContainsKey('Owner') -and $PSBoundParameters.ContainsKey('Organization'))
    {
        throw 'Use only one of -Owner or -Organization.'
    }

    if ($AllAuthors -and $PSBoundParameters.ContainsKey('Author'))
    {
        throw 'Use either -Author or -AllAuthors, not both.'
    }

    if (
        $AllAuthors -and
        -not $PSBoundParameters.ContainsKey('Owner') -and
        -not $PSBoundParameters.ContainsKey('Organization') -and
        -not $PSBoundParameters.ContainsKey('Repository')
    )
    {
        throw 'Use -AllAuthors only with -Owner, -Organization, or -Repository.'
    }

    $repositoryContext = if ($PSBoundParameters.ContainsKey('Repository'))
    {
        & $helpers.ParseRepositorySpecifier $Repository
    }
    else
    {
        $null
    }

    $resolveGitHubPullRequestSearchHostParams = @{
        RequestedHost = $GitHubHost
        RepositoryContext = $repositoryContext
        GitHubHostWasSpecified = $PSBoundParameters.ContainsKey('GitHubHost')
    }
    $searchHost = Resolve-GitHubPullRequestSearchHost @resolveGitHubPullRequestSearchHostParams
    $transport = & $helpers.ResolveTransport
    $targetDisplay = 'GitHub pull requests'
    $stateDisplay = $State.ToLowerInvariant()

    try
    {
        $resolveAuthContextParams = @{
            Token = $Token
            TokenEnvironmentVariableName = $TokenEnvironmentVariableName
            RequireToken = ($transport.Name -ne 'GhCli')
        }
        $authContext = & $helpers.ResolveAuthContext @resolveAuthContextParams

        $effectiveAuthor = $null
        if (-not $AllAuthors)
        {
            $effectiveAuthor = if ($PSBoundParameters.ContainsKey('Author')) { $Author.Trim() } else { $null }
            if ([string]::IsNullOrWhiteSpace($effectiveAuthor) -or $effectiveAuthor -eq '@me')
            {
                $resolveGitHubCurrentUserLoginParams = @{
                    BaseUri = $searchHost.BaseUri
                    Transport = $transport
                    AuthContext = $authContext
                    MaxRetryCount = $maxRetryCount
                    InitialRetryDelaySeconds = $initialRetryDelaySeconds
                }
                $effectiveAuthor = Resolve-GitHubCurrentUserLogin @resolveGitHubCurrentUserLoginParams
            }
        }

        $queryParts = New-Object System.Collections.Generic.List[String]
        $queryParts.Add('is:pr') | Out-Null

        switch ($State)
        {
            'Open'
            {
                $queryParts.Add('state:open') | Out-Null
            }
            'Closed'
            {
                $queryParts.Add('state:closed') | Out-Null
                $queryParts.Add('-is:merged') | Out-Null
            }
            'Merged'
            {
                $queryParts.Add('is:merged') | Out-Null
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($effectiveAuthor))
        {
            $queryParts.Add("author:$effectiveAuthor") | Out-Null
        }

        if ($PSBoundParameters.ContainsKey('Organization'))
        {
            $queryParts.Add("org:$($Organization.Trim())") | Out-Null
        }

        if ($PSBoundParameters.ContainsKey('Owner'))
        {
            $queryParts.Add("user:$($Owner.Trim())") | Out-Null
        }

        if ($repositoryContext)
        {
            $queryParts.Add("repo:$($repositoryContext.NameWithOwner)") | Out-Null
        }

        $query = $queryParts -join ' '
        $targetParts = New-Object System.Collections.Generic.List[String]
        if (-not [string]::IsNullOrWhiteSpace($effectiveAuthor))
        {
            $targetParts.Add("authored by $effectiveAuthor") | Out-Null
        }
        elseif ($AllAuthors)
        {
            $targetParts.Add('from all authors') | Out-Null
        }

        if ($PSBoundParameters.ContainsKey('Organization'))
        {
            $targetParts.Add("in organization $($Organization.Trim())") | Out-Null
        }

        if ($PSBoundParameters.ContainsKey('Owner'))
        {
            $targetParts.Add("in repositories owned by $($Owner.Trim())") | Out-Null
        }

        if ($repositoryContext)
        {
            $targetParts.Add("in repository $($repositoryContext.NameWithOwner)") | Out-Null
        }

        $targetDisplay = if ($targetParts.Count -gt 0)
        {
            $targetParts -join ' '
        }
        else
        {
            'GitHub pull requests'
        }

        $allItems = New-Object System.Collections.Generic.List[Object]
        $perPage = 100
        $page = 1
        $totalCount = 0
        $incompleteResults = $false
        $searchResultLimit = 1000

        do
        {
            $encodedQuery = [Uri]::EscapeDataString($query)
            $path = "/search/issues?q=$encodedQuery&sort=updated&order=desc&per_page=$perPage&page=$page"
            $invokeGitHubRequestParams = @{
                Method = 'GET'
                BaseUri = $searchHost.BaseUri
                Path = $path
                Transport = $transport
                AuthContext = $authContext
                Body = $null
                MaxRetryCount = $maxRetryCount
                InitialRetryDelaySeconds = $initialRetryDelaySeconds
                Activity = "Search $stateDisplay pull requests"
            }
            $searchResult = & $helpers.InvokeGitHubRequest @invokeGitHubRequestParams
            $pageItems = @($searchResult.items)

            if ($page -eq 1)
            {
                $totalCount = [int]$searchResult.total_count
                $incompleteResults = [bool]$searchResult.incomplete_results
            }

            foreach ($item in $pageItems)
            {
                $allItems.Add($item) | Out-Null
            }

            $page++
        } while (
            $pageItems.Count -eq $perPage -and
            $allItems.Count -lt $totalCount -and
            $allItems.Count -lt $searchResultLimit
        )

        $pullRequests = @($allItems | ForEach-Object { ConvertTo-GitHubPullRequestResult -Item $_ })
        $searchResultLimitReached = ($totalCount -gt $pullRequests.Count)

        return & $helpers.NewOperationResult -TypeName 'GitHub.PullRequestSearch' -Properties @{
            PullRequests = $pullRequests
            PullRequestCount = $pullRequests.Count
            TotalCount = $totalCount
            State = $State
            Query = $query
            Target = $targetDisplay
            Author = $effectiveAuthor
            AllAuthors = [bool]$AllAuthors
            Organization = if ($PSBoundParameters.ContainsKey('Organization')) { $Organization.Trim() } else { $null }
            Owner = if ($PSBoundParameters.ContainsKey('Owner')) { $Owner.Trim() } else { $null }
            Repository = if ($repositoryContext) { $repositoryContext.GhRepository } else { $null }
            GitHubHost = $searchHost.Host
            SearchResultLimitReached = $searchResultLimitReached
            IncompleteResults = $incompleteResults
            Transport = $transport.Name
            Authentication = $authContext.Source
        }
    }
    catch
    {
        $getFriendlyErrorMessageParams = @{
            Operation = 'get pull requests'
            Name = $stateDisplay
            Target = $targetDisplay
            Exception = $_.Exception
        }
        $friendlyMessage = & $helpers.GetFriendlyErrorMessage @getFriendlyErrorMessageParams

        throw $friendlyMessage
    }
}
