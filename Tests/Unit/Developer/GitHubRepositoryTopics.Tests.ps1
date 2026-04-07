#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Get-GitHubRepositoryTopic.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Set-GitHubRepositoryTopic.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitHubRepositoryTopic.ps1"

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

    $script:TokenValue = ConvertTo-TestSecureString 'ghp_test_token_123'
}

Describe 'GitHub repository topic functions' {
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
        It 'does not load shared helpers when the function files are dot-sourced' {
            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Get-GitHubRepositoryTopic' {
        It 'returns all topics for a repository' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubRepositoryTopic -Repository 'octo-org/service-api'

            $result.Repository | Should -Be 'octo-org/service-api'
            $result.Topics | Should -Be @('powershell', 'automation')
            $result.AllTopics | Should -Be @('powershell', 'automation')
            $result.MissingTopics | Should -BeNullOrEmpty
            $result.TopicCount | Should -Be 2
        }

        It 'filters requested topics and reports missing topic names' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Get-GitHubRepositoryTopic -Name @(' PowerShell ', 'Missing', 'powershell') -Repository 'octo-org/service-api'

            $result.RequestedTopics | Should -Be @('powershell', 'missing')
            $result.Topics | Should -Be @('powershell')
            $result.MissingTopics | Should -Be @('missing')
            $result.TotalTopicCount | Should -Be 2
        }
    }

    Context 'Set-GitHubRepositoryTopic' {
        It 'returns Unchanged when all requested topics are already present' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubRepositoryTopic -Name @('Automation', ' powershell ') -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Unchanged'
            $result.Changed | Should -BeFalse
            $result.Topics | Should -Be @('powershell', 'automation')
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains 'PUT'
            } -Times 0
        }

        It 'normalizes topic names and adds only missing topics' {
            $script:TempRequestBodies = @()

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation"]}'
                }

                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'PUT')
                {
                    $inputIndex = [Array]::IndexOf($args, '--input')
                    if ($inputIndex -ge 0)
                    {
                        $script:TempRequestBodies += [System.IO.File]::ReadAllText($args[$inputIndex + 1])
                    }

                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation","devops"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubRepositoryTopic -Name @(' PowerShell ', 'DevOps', 'devops ') -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Updated'
            $result.AddedTopics | Should -Be @('devops')
            $result.Topics | Should -Be @('powershell', 'automation', 'devops')
            $script:TempRequestBodies.Count | Should -Be 1
            $script:TempRequestBodies[0] | Should -Match '"names":\["powershell","automation","devops"\]'
        }

        It 'falls back to the REST API when gh is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }

            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Method -eq 'GET' -and $Uri -eq 'https://api.github.com/repos/octo-org/service-api/topics')
                {
                    return [PSCustomObject]@{
                        names = @('powershell')
                    }
                }

                if ($Method -eq 'PUT' -and $Uri -eq 'https://api.github.com/repos/octo-org/service-api/topics')
                {
                    $Body | Should -Match '"names":\["powershell","automation"\]'

                    return [PSCustomObject]@{
                        names = @('powershell', 'automation')
                    }
                }

                throw "Unexpected REST request: $Method $Uri"
            }

            $result = Set-GitHubRepositoryTopic `
                -Name 'Automation' `
                -Repository 'octo-org/service-api' `
                -Token $script:TokenValue

            $result.Status | Should -Be 'Updated'
            $result.Transport | Should -Be 'RestApi'
            $result.Topics | Should -Be @('powershell', 'automation')
        }
    }

    Context 'Remove-GitHubRepositoryTopic' {
        It 'returns AlreadyAbsent when all requested topics are already missing' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubRepositoryTopic -Name @('missing', ' Missing ') -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'AlreadyAbsent'
            $result.Changed | Should -BeFalse
            $result.Topics | Should -Be @('powershell', 'automation')
            Assert-MockCalled -CommandName gh -ParameterFilter {
                $args[0] -eq 'api' -and $args -contains 'PUT'
            } -Times 0
        }

        It 'removes only requested existing topics and preserves unrelated topics' {
            $script:TempRequestBodies = @()

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'GET')
                {
                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","automation","devops"]}'
                }

                if ($args[0] -eq 'api' -and $args -contains '/repos/octo-org/service-api/topics' -and $args -contains 'PUT')
                {
                    $inputIndex = [Array]::IndexOf($args, '--input')
                    if ($inputIndex -ge 0)
                    {
                        $script:TempRequestBodies += [System.IO.File]::ReadAllText($args[$inputIndex + 1])
                    }

                    $global:LASTEXITCODE = 0
                    return '{"names":["powershell","devops"]}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubRepositoryTopic -Name @('Automation', 'missing') -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Removed'
            $result.RemovedTopics | Should -Be @('automation')
            $result.Topics | Should -Be @('powershell', 'devops')
            $script:TempRequestBodies.Count | Should -Be 1
            $script:TempRequestBodies[0] | Should -Match '"names":\["powershell","devops"\]'
        }
    }
}
