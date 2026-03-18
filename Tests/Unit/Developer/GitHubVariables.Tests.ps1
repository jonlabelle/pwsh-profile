#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Set-GitHubVariable.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Get-GitHubVariable.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitHubVariable.ps1"

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

    function Import-GitHubHelperForTest
    {
        if (-not (Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue))
        {
            . "$PSScriptRoot/../../../Functions/Developer/Private/GitHubConfigurationHelpers.ps1"
        }

        return (Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script).Value
    }

    $script:TokenValue = ConvertTo-TestSecureString 'ghp_test_token_123'
}

Describe 'GitHub variable functions' {
    BeforeEach {
        Remove-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0

        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith {
            [PSCustomObject]@{
                Name = 'gh'
                Source = '/usr/local/bin/gh'
            }
        }
    }

    AfterEach {
        Remove-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue
    }

    Context 'Dependency loading' {
        It 'does not load shared helpers when the function files are dot-sourced' {
            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Set-GitHubVariable' {
        It 'rejects invalid variable names before making GitHub calls' -ForEach @(
            @{ Name = 'INVALID NAME'; Error = '*letters, numbers, or underscores*' }
            @{ Name = '1INVALID'; Error = '*cannot start with a number*' }
            @{ Name = 'GITHUB_TOKEN'; Error = "*cannot start with the 'GITHUB_' prefix*" }
        ) {
            {
                Set-GitHubVariable -Name $Name -Value 'enabled' -Repository 'octo-org/service-api'
            } | Should -Throw $Error

            {
                Get-GitHubVariable -Name $Name -Repository 'octo-org/service-api'
            } | Should -Throw $Error

            {
                Remove-GitHubVariable -Name $Name -Repository 'octo-org/service-api'
            } | Should -Throw $Error
        }

        It 'rejects environment names longer than 255 characters' {
            $tooLongEnvironmentName = 'a' * 256

            {
                Set-GitHubVariable `
                    -Name 'DEPLOY_RING' `
                    -Value 'production' `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'

            {
                Get-GitHubVariable `
                    -Name 'DEPLOY_RING' `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'

            {
                Remove-GitHubVariable `
                    -Name 'DEPLOY_RING' `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'
        }

        It 'accepts environment names that contain slashes' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/environments/Production%2FBlue/variables/DEPLOY_RING')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"DEPLOY_RING","value":"production","visibility":"private"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubVariable `
                -Name 'DEPLOY_RING' `
                -Repository 'octo-org/service-api' `
                -Environment 'Production/Blue'

            $result.Name | Should -Be 'DEPLOY_RING'
            $result.Target | Should -Be "environment 'Production/Blue' in octo-org/service-api"
        }

        It 'returns Unchanged when the existing value already matches' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/DOTNET_VERSION')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"DOTNET_VERSION","value":"8.0.x","visibility":"private"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubVariable -Name 'DOTNET_VERSION' -Value '8.0.x' -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Unchanged'
            $result.Changed | Should -BeFalse
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains '--method' -and $args -contains 'PATCH'
            } -Times 0
        }

        It 'skips existing variables without -Force when the value differs' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/DOTNET_VERSION')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"DOTNET_VERSION","value":"7.0.x","visibility":"private"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubVariable -Name 'DOTNET_VERSION' -Value '8.0.x' -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Skipped'
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains '--method' -and ($args -contains 'PATCH' -or $args -contains 'POST')
            } -Times 0
        }

        It 'updates existing variables when -Force is used' {
            $script:TempRequestBodies = @()

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/DOTNET_VERSION' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"DOTNET_VERSION","value":"7.0.x","visibility":"private"}'
                }

                if ($args[0] -eq 'api' -and $args -contains 'PATCH')
                {
                    $inputIndex = [Array]::IndexOf($args, '--input')
                    if ($inputIndex -ge 0)
                    {
                        $script:TempRequestBodies += [System.IO.File]::ReadAllText($args[$inputIndex + 1])
                    }

                    $global:LASTEXITCODE = 0
                    return '{"name":"DOTNET_VERSION","value":"8.0.x","visibility":"private"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubVariable -Name 'DOTNET_VERSION' -Value '8.0.x' -Repository 'octo-org/service-api' -Force

            $result.Status | Should -Be 'Updated'
            $script:TempRequestBodies.Count | Should -Be 1
            $script:TempRequestBodies[0] | Should -Match '"value":"8.0.x"'
        }

        It 'falls back to the REST API when gh is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }

            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/orgs/octo-org/actions/variables/REGION')
                {
                    $exception = [System.InvalidOperationException]::new('Not Found')
                    $exception.Data['StatusCode'] = 404
                    throw $exception
                }

                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/repos/octo-org/app1')
                {
                    return [PSCustomObject]@{ id = 101 }
                }

                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/repos/octo-org/app2')
                {
                    return [PSCustomObject]@{ id = 102 }
                }

                if ($Method -eq 'POST' -and $Uri -eq 'https://api.github.com/orgs/octo-org/actions/variables')
                {
                    $Body | Should -Match '"visibility":"selected"'
                    $Body | Should -Match '"selected_repository_ids":\[101,102\]'
                    return $null
                }

                throw "Unexpected REST request: $Method $Uri"
            }

            $result = Set-GitHubVariable `
                -Name 'REGION' `
                -Value 'us-east-1' `
                -Organization 'octo-org' `
                -SelectedRepository @('app1', 'app2') `
                -Token $script:TokenValue

            $result.Status | Should -Be 'Created'
            $result.Transport | Should -Be 'RestApi'
        }

        It 'retries transient API failures with exponential backoff' {
            $script:CreateAttempts = 0

            Mock -CommandName Start-Sleep -MockWith {}
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/FEATURE_FLAG' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                if ($args[0] -eq 'api' -and $args -contains 'POST')
                {
                    $script:CreateAttempts++
                    if ($script:CreateAttempts -eq 1)
                    {
                        $global:LASTEXITCODE = 1
                        return 'HTTP 503: Service Unavailable'
                    }

                    $global:LASTEXITCODE = 0
                    return '{"name":"FEATURE_FLAG","value":"enabled"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubVariable -Name 'FEATURE_FLAG' -Value 'enabled' -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Created'
            $script:CreateAttempts | Should -Be 2
            Assert-MockCalled -CommandName Start-Sleep -Times 1
        }
    }

    Context 'Get-GitHubVariable' {
        It 'normalizes snake_case REST fields in fallback mode' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }
            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/orgs/octo-org/actions/variables/REGION')
                {
                    return [PSCustomObject]@{
                        name = 'REGION'
                        value = 'us-east-1'
                        visibility = 'selected'
                        created_at = '2025-01-01T00:00:00Z'
                        updated_at = '2025-01-02T00:00:00Z'
                        num_selected_repos = 2
                        selected_repositories_url = 'https://api.github.com/orgs/octo-org/actions/variables/REGION/repositories'
                    }
                }

                throw "Unexpected REST request: $Method $Uri"
            }

            $result = Get-GitHubVariable -Name 'REGION' -Organization 'octo-org' -Token $script:TokenValue

            $result.Name | Should -Be 'REGION'
            $result.Value | Should -Be 'us-east-1'
            $result.NumSelectedRepos | Should -Be 2
            $result.SelectedReposUrl | Should -Be 'https://api.github.com/orgs/octo-org/actions/variables/REGION/repositories'
        }

        It 'redacts the GitHub token from REST fallback errors' {
            $redactionToken = ConvertTo-TestSecureString 'ghp_Abc123Sensitive'

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }
            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/orgs/octo-org/actions/variables/REGION')
                {
                    throw [System.InvalidOperationException]::new('request failed for ghp_Abc123Sensitive')
                }

                throw "Unexpected REST request: $Method $Uri"
            }

            try
            {
                Get-GitHubVariable -Name 'REGION' -Organization 'octo-org' -Token $redactionToken | Out-Null
                throw 'Expected Get-GitHubVariable to fail.'
            }
            catch
            {
                $_.Exception.Message | Should -Not -Match 'ghp_Abc123Sensitive'
                $_.Exception.Message | Should -Match '\[REDACTED\]'
            }
        }
    }

    Context 'Helper behaviors' {
        It 'defaults missing REST auth guidance to GH_TOKEN when no auth context exists' {
            $helpers = Import-GitHubHelperForTest

            {
                & $helpers.InvokeGitHubRequest `
                    -Method 'GET' `
                    -BaseUri 'https://api.github.com' `
                    -Path '/user' `
                    -Transport ([PSCustomObject]@{ Name = 'RestApi'; Command = $null }) `
                    -AuthContext $null `
                    -Body $null `
                    -MaxRetryCount 0 `
                    -InitialRetryDelaySeconds 1 `
                    -Activity 'Get GitHub user'
            } | Should -Throw "*'GH_TOKEN'*"
        }
    }

    Context 'Remove-GitHubVariable' {
        It 'returns AlreadyAbsent when the variable does not exist' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/MISSING_FLAG')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubVariable -Name 'MISSING_FLAG' -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'AlreadyAbsent'
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains '--method' -and $args -contains 'DELETE'
            } -Times 0
        }

        It 'supports WhatIf without deleting the variable' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/actions/variables/FEATURE_FLAG')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"FEATURE_FLAG","value":"enabled","visibility":"private"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubVariable -Name 'FEATURE_FLAG' -Repository 'octo-org/service-api' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains '--method' -and $args -contains 'DELETE'
            } -Times 0
        }
    }
}
