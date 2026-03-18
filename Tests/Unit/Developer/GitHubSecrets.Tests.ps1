#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Set-GitHubSecret.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitHubSecret.ps1"

    function Reset-GitHubHelperState
    {
        Remove-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue
    }

    $script:SecretValue = ConvertTo-SecureString 'SuperSecretValue123!' -AsPlainText -Force
    $script:TokenValue = ConvertTo-SecureString 'ghp_test_token_123' -AsPlainText -Force
}

Describe 'GitHub secret functions' {
    BeforeEach {
        Reset-GitHubHelperState
        $global:LASTEXITCODE = 0

        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith {
            [PSCustomObject]@{
                Name = 'gh'
                Source = '/usr/local/bin/gh'
            }
        }
    }

    AfterEach {
        Reset-GitHubHelperState
    }

    Context 'Dependency loading' {
        It 'does not load shared helpers when the function files are dot-sourced' {
            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }

        It 'loads shared helpers lazily on first invocation' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            Set-GitHubSecret -Name 'LAZY_LOAD_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api' -WhatIf | Out-Null

            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-GitHubSecret' {
        It 'skips existing secrets without -Force' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"EXISTING_SECRET","updated_at":"2025-01-01T00:00:00Z"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubSecret -Name 'EXISTING_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Skipped'
            $result.Changed | Should -BeFalse
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'set' } -Times 0
        }

        It 'updates existing secrets when -Force is used' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"EXISTING_SECRET","updated_at":"2025-01-01T00:00:00Z"}'
                }

                if ($args[0] -eq 'secret' -and $args[1] -eq 'set')
                {
                    $global:LASTEXITCODE = 0
                    return @()
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubSecret -Name 'EXISTING_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api' -Force

            $result.Status | Should -Be 'Updated'
            $result.Changed | Should -BeTrue
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'set' } -Times 1
        }

        It 'supports WhatIf without calling gh secret set' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubSecret -Name 'NEW_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'set' } -Times 0
        }

        It 'throws a clear error when gh is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }

            {
                Set-GitHubSecret -Name 'REST_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api' -Token $script:TokenValue
            } | Should -Throw '*GitHub CLI*'
        }
    }

    Context 'Remove-GitHubSecret' {
        It 'returns AlreadyAbsent when the secret does not exist' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubSecret -Name 'MISSING_SECRET' -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'AlreadyAbsent'
            $result.Changed | Should -BeFalse
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'delete' } -Times 0
        }

        It 'supports WhatIf without deleting the secret' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"TO_DELETE","updated_at":"2025-01-01T00:00:00Z"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubSecret -Name 'TO_DELETE' -Repository 'octo-org/service-api' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'delete' } -Times 0
        }
    }
}
