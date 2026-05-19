#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Get-GitHubPullRequest.ps1"

    function ConvertTo-TestSecureString
    {
        param([String]$Value)

        $secureString = New-Object System.Security.SecureString
        foreach ($character in $Value.ToCharArray())
        {
            $secureString.AppendChar($character)
        }

        $secureString.MakeReadOnly()
        return $secureString
    }

    function Get-TestSearchQuery
    {
        param([String]$Path)

        if ($Path -notmatch '[?&]q=([^&]+)')
        {
            return $null
        }

        return [Uri]::UnescapeDataString($matches[1])
    }

    function Get-TestPullRequestSearchResponse
    {
        param(
            [Int]$TotalCount,
            [Object[]]$Items
        )

        return @{
            total_count = $TotalCount
            incomplete_results = $false
            items = @($Items)
        } | ConvertTo-Json -Depth 10 -Compress
    }

    function Get-TestPullRequestItem
    {
        param(
            [String]$Repository = 'octo-org/service-api',
            [Int]$Number = 42,
            [String]$Title = 'Improve deployment workflow',
            [String]$State = 'open',
            [String]$Author = 'octocat',
            [String]$MergedAt = $null
        )

        return @{
            repository_url = "https://api.github.com/repos/$Repository"
            number = $Number
            title = $Title
            state = $State
            draft = $false
            user = @{
                login = $Author
            }
            html_url = "https://github.com/$Repository/pull/$Number"
            pull_request = @{
                url = "https://api.github.com/repos/$Repository/pulls/$Number"
                html_url = "https://github.com/$Repository/pull/$Number"
                merged_at = $MergedAt
            }
            labels = @(
                @{
                    name = 'enhancement'
                }
            )
            comments = 3
            created_at = '2026-01-01T00:00:00Z'
            updated_at = '2026-01-02T00:00:00Z'
            closed_at = if ($State -eq 'closed') { '2026-01-03T00:00:00Z' } else { $null }
        }
    }

    $script:TokenValue = ConvertTo-TestSecureString 'ghp_test_token_123'
}

Describe 'GitHub pull request function' {
    BeforeEach {
        Remove-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0

        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith {
            [PSCustomObject]@{
                Name = 'gh'
                Source = 'gh'
                Path = 'gh'
                Definition = 'gh'
            }
        }
    }

    AfterEach {
        Remove-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue
    }

    Context 'Dependency loading' {
        It 'does not load shared helpers when the function file is dot-sourced' {
            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Get-GitHubPullRequest' {
        It 'returns open pull requests for the authenticated user by default' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/user')
                {
                    $global:LASTEXITCODE = 0
                    return '{"login":"octocat"}'
                }

                if ($args[0] -eq 'api' -and $args[-1] -like '/search/issues*')
                {
                    $query = Get-TestSearchQuery -Path $args[-1]
                    $query | Should -Be 'is:pr state:open author:octocat'

                    $global:LASTEXITCODE = 0
                    return Get-TestPullRequestSearchResponse -TotalCount 1 -Items @(
                        (Get-TestPullRequestItem -Author 'octocat')
                    )
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubPullRequest

            $result.State | Should -Be 'Open'
            $result.Author | Should -Be 'octocat'
            $result.PullRequestCount | Should -Be 1
            $result.PullRequests[0].Repository | Should -Be 'octo-org/service-api'
            $result.PullRequests[0].Number | Should -Be 42
            $result.PullRequests[0].IsMerged | Should -BeFalse
        }

        It 'searches merged pull requests for a specified author without resolving the current user' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/user')
                {
                    throw 'The current user should not be resolved when -Author is provided.'
                }

                if ($args[0] -eq 'api' -and $args[-1] -like '/search/issues*')
                {
                    $query = Get-TestSearchQuery -Path $args[-1]
                    $query | Should -Be 'is:pr is:merged author:hubot'

                    $global:LASTEXITCODE = 0
                    return Get-TestPullRequestSearchResponse -TotalCount 1 -Items @(
                        (Get-TestPullRequestItem -State 'closed' -Author 'hubot' -MergedAt '2026-01-03T00:00:00Z')
                    )
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubPullRequest -Author 'hubot' -State Merged

            $result.Query | Should -Be 'is:pr is:merged author:hubot'
            $result.PullRequests[0].IsMerged | Should -BeTrue
            ([DateTime]$result.PullRequests[0].MergedAt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-01-03T00:00:00Z'
        }

        It 'uses the closed unmerged search qualifiers for closed pull requests' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args[-1] -like '/search/issues*')
                {
                    $query = Get-TestSearchQuery -Path $args[-1]
                    $query | Should -Be 'is:pr state:closed -is:merged author:octocat'

                    $global:LASTEXITCODE = 0
                    return Get-TestPullRequestSearchResponse -TotalCount 0 -Items @()
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubPullRequest -Author 'octocat' -State Closed

            $result.Query | Should -Be 'is:pr state:closed -is:merged author:octocat'
            $result.PullRequestCount | Should -Be 0
        }

        It 'supports repository-scoped searches from all authors' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/user')
                {
                    throw 'The current user should not be resolved when -AllAuthors is used.'
                }

                if ($args[0] -eq 'api' -and $args[-1] -like '/search/issues*')
                {
                    $query = Get-TestSearchQuery -Path $args[-1]
                    $query | Should -Be 'is:pr state:open repo:octo-org/service-api'

                    $global:LASTEXITCODE = 0
                    return Get-TestPullRequestSearchResponse -TotalCount 1 -Items @(
                        (Get-TestPullRequestItem -Author 'monalisa')
                    )
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubPullRequest -Repository 'octo-org/service-api' -AllAuthors

            $result.Author | Should -BeNullOrEmpty
            $result.AllAuthors | Should -BeTrue
            $result.Repository | Should -Be 'octo-org/service-api'
            $result.PullRequests[0].Author | Should -Be 'monalisa'
        }

        It 'retrieves all available search pages with the REST fallback' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }

            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Method -eq 'GET' -and $Uri -like 'https://api.github.com/search/issues*page=1')
                {
                    $query = Get-TestSearchQuery -Path $Uri
                    $query | Should -Be 'is:pr state:open author:octocat org:octo-org'

                    return [PSCustomObject]@{
                        total_count = 101
                        incomplete_results = $false
                        items = @(1..100 | ForEach-Object {
                                [PSCustomObject](Get-TestPullRequestItem -Number $_ -Author 'octocat')
                            })
                    }
                }

                if ($Method -eq 'GET' -and $Uri -like 'https://api.github.com/search/issues*page=2')
                {
                    return [PSCustomObject]@{
                        total_count = 101
                        incomplete_results = $false
                        items = @(
                            [PSCustomObject](Get-TestPullRequestItem -Number 101 -Author 'octocat')
                        )
                    }
                }

                throw "Unexpected REST request: $Method $Uri"
            }

            $result = Get-GitHubPullRequest -Author 'octocat' -Organization 'octo-org' -Token $script:TokenValue

            $result.Transport | Should -Be 'RestApi'
            $result.PullRequestCount | Should -Be 101
            $result.TotalCount | Should -Be 101
            $result.SearchResultLimitReached | Should -BeFalse
        }

        It 'requires a scope filter when searching all authors' {
            {
                Get-GitHubPullRequest -AllAuthors
            } | Should -Throw '*Use -AllAuthors only with -Owner, -Organization, or -Repository*'
        }

        It 'rejects owner and organization filters together' {
            {
                Get-GitHubPullRequest -Owner 'octocat' -Organization 'octo-org'
            } | Should -Throw '*Use only one of -Owner or -Organization*'
        }
    }
}
