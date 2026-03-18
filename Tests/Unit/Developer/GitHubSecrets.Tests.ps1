#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Set-GitHubSecret.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitHubSecret.ps1"

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

    $script:SecretValue = ConvertTo-TestSecureString 'SuperSecretValue123!'
    $script:TokenValue = ConvertTo-TestSecureString 'ghp_test_token_123'
}

Describe 'GitHub secret functions' {
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
        It 'rejects invalid secret names before making GitHub calls' -ForEach @(
            @{ Name = 'INVALID NAME'; Error = '*letters, numbers, or underscores*' }
            @{ Name = '1INVALID'; Error = '*cannot start with a number*' }
            @{ Name = 'GITHUB_TOKEN'; Error = "*cannot start with the 'GITHUB_' prefix*" }
        ) {
            {
                Set-GitHubSecret -Name $Name -Value $script:SecretValue -Repository 'octo-org/service-api'
            } | Should -Throw $Error

            {
                Remove-GitHubSecret -Name $Name -Repository 'octo-org/service-api'
            } | Should -Throw $Error
        }

        It 'rejects environment names longer than 255 characters' {
            $tooLongEnvironmentName = 'a' * 256

            {
                Set-GitHubSecret `
                    -Name 'DEPLOY_TOKEN' `
                    -Value $script:SecretValue `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'

            {
                Remove-GitHubSecret `
                    -Name 'DEPLOY_TOKEN' `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'
        }

        It 'accepts environment names that contain slashes' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubSecret `
                -Name 'DEPLOY_TOKEN' `
                -Value $script:SecretValue `
                -Repository 'octo-org/service-api' `
                -Environment 'Production/Blue' `
                -WhatIf

            $result.Status | Should -Be 'WhatIf'
        }

        It 'rejects secret values larger than 48 KB before making GitHub calls' {
            $tooLargeValue = ConvertTo-TestSecureString ('a' * 49153)

            Mock -CommandName gh -MockWith {
                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            {
                Set-GitHubSecret -Name 'OVERSIZED_SECRET' -Value $tooLargeValue -Repository 'octo-org/service-api'
            } | Should -Throw '*48 KB*'

            Assert-MockCalled -CommandName gh -Times 0
        }

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
            $script:CapturedSecretSetArguments = $null
            $script:CapturedSecretStandardInput = $null

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"EXISTING_SECRET","updated_at":"2025-01-01T00:00:00Z"}'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $helpers = Import-GitHubHelperForTest
            $helpers.StartGhCommandWithStandardInput = {
                param(
                    [String[]]$Arguments,
                    [String]$StandardInputText
                )

                $script:CapturedSecretSetArguments = @($Arguments)
                $script:CapturedSecretStandardInput = $StandardInputText

                return [PSCustomObject]@{
                    ExitCode = 0
                    StandardOutput = ''
                    StandardError = ''
                }
            }

            $result = Set-GitHubSecret -Name 'EXISTING_SECRET' -Value $script:SecretValue -Repository 'octo-org/service-api' -Force

            $result.Status | Should -Be 'Updated'
            $result.Changed | Should -BeTrue
            $script:CapturedSecretSetArguments | Should -Not -Contain '--body'
            $script:CapturedSecretStandardInput | Should -Be 'SuperSecretValue123!'
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

        It 'redacts the secret value and token from thrown errors' {
            $redactionToken = ConvertTo-TestSecureString 'ghp_Abc123Sensitive'

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw 'Unexpected gh invocation'
            }

            $helpers = Import-GitHubHelperForTest
            $helpers.StartGhCommandWithStandardInput = {
                param(
                    [String[]]$Arguments,
                    [String]$StandardInputText
                )

                $null = @($Arguments)
                $null = $StandardInputText

                return [PSCustomObject]@{
                    ExitCode = 1
                    StandardOutput = ''
                    StandardError = 'validation failed for SuperSecretValue123! with credential ghp_Abc123Sensitive'
                }
            }

            try
            {
                Set-GitHubSecret -Name 'REDACTION_TEST' -Value $script:SecretValue -Repository 'octo-org/service-api' -Token $redactionToken
                throw 'Expected Set-GitHubSecret to fail.'
            }
            catch
            {
                $_.Exception.Message | Should -Not -Match 'SuperSecretValue123!'
                $_.Exception.Message | Should -Not -Match 'ghp_Abc123Sensitive'
                $_.Exception.Message | Should -Match '\[REDACTED\]'
            }
        }
    }

    Context 'Helper behaviors' {
        It 'resolves auth safely when a process token is absent on non-Windows platforms' {
            $helpers = Import-GitHubHelperForTest

            {
                & $helpers.ResolveAuthContext `
                    -Token $null `
                    -TokenEnvironmentVariableName 'PWSH_PROFILE_MISSING_GH_TOKEN' `
                    -RequireToken:$false
            } | Should -Not -Throw
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
