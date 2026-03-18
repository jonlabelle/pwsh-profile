#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/Developer/Set-GitHubSecret.ps1"
    . "$PSScriptRoot/../../../Functions/Developer/Remove-GitHubSecret.ps1"

    function Invoke-TestGhBinary
    {
    }

    function Invoke-TestGitBinary
    {
    }

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

        It 'loads shared helpers lazily on first invocation' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            Set-GitHubSecret -Name 'LAZY_LOAD_SECRET' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api' -WhatIf | Out-Null

            Get-Variable -Name PwshProfileGitHubConfigurationHelpers -Scope Script -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Set-GitHubSecret' {
        It 'supports user scope through -Scope User' {
            $script:CapturedSecretSetArguments = $null

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
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
                $null = $StandardInputText

                return [PSCustomObject]@{
                    ExitCode = 0
                    StandardOutput = ''
                    StandardError = ''
                }
            }

            $result = Set-GitHubSecret -Name 'DEVCONTAINER_PAT' -Value $script:SecretValue -Scope User

            $result.Status | Should -Be 'Created'
            $script:CapturedSecretSetArguments | Should -Contain '--user'
            $script:CapturedSecretSetArguments | Should -Not -Contain '--app'
        }

        It 'normalizes and de-duplicates selected repositories for -Scope User' {
            $script:CapturedSecretSetArguments = $null

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
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
                $null = $StandardInputText

                return [PSCustomObject]@{
                    ExitCode = 0
                    StandardOutput = ''
                    StandardError = ''
                }
            }

            $result = Set-GitHubSecret `
                -Name 'DEVCONTAINER_PAT' `
                -Value $script:SecretValue `
                -Scope User `
                -SelectedRepository @(' octo-org/service-api ', 'octo-org/service-api ')

            $reposIndex = [Array]::IndexOf($script:CapturedSecretSetArguments, '--repos')

            $result.Status | Should -Be 'Created'
            $reposIndex | Should -BeGreaterThan -1
            $script:CapturedSecretSetArguments[$reposIndex + 1] | Should -Be 'octo-org/service-api'
        }

        It 'rejects repository targeting for -Scope User' {
            {
                Set-GitHubSecret `
                    -Name 'DEVCONTAINER_PAT' `
                    -Value $script:SecretValue `
                    -Scope User `
                    -Repository 'octo-org/service-api'
            } | Should -Throw '*-Scope User does not support -Repository*'
        }

        It 'rejects bare selected repository names for -Scope User' {
            {
                Set-GitHubSecret `
                    -Name 'DEVCONTAINER_PAT' `
                    -Value $script:SecretValue `
                    -Scope User `
                    -SelectedRepository 'service-api'
            } | Should -Throw '*must use OWNER/REPO format*'
        }

        It 'supports environment scope through -Scope Environment' {
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
                -Scope Environment `
                -Repository 'octo-org/service-api' `
                -Environment 'Production' `
                -WhatIf

            $result.Status | Should -Be 'WhatIf'
            $result.Scope | Should -Be 'Environment'
            $result.Target | Should -Be "environment 'Production' in octo-org/service-api"
        }

        It 'supports organization scope through -Scope Organization' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Set-GitHubSecret `
                -Name 'ORG_SECRET' `
                -Value $script:SecretValue `
                -Scope Organization `
                -Organization 'octo-org' `
                -WhatIf

            $result.Status | Should -Be 'WhatIf'
            $result.Scope | Should -Be 'Organization'
            $result.Target | Should -Be 'organization octo-org'
        }

        It 'rejects non-codespaces applications for -Scope User' {
            {
                Set-GitHubSecret `
                    -Name 'DEVCONTAINER_PAT' `
                    -Value $script:SecretValue `
                    -Scope User `
                    -Application actions
            } | Should -Throw '*User secrets support only the codespaces application*'
        }

        It 'rejects invalid secret names before making GitHub calls' -ForEach @(
            @{ Name = 'INVALID NAME'; Error = '*letters, numbers, or underscores*' }
            @{ Name = '1INVALID'; Error = '*cannot start with a number*' }
            @{ Name = 'GITHUB_TOKEN'; Error = "*cannot start with the 'GITHUB_' prefix*" }
        ) {
            {
                Set-GitHubSecret -Name $Name -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api'
            } | Should -Throw $Error

            {
                Remove-GitHubSecret -Name $Name -Scope Repository -Repository 'octo-org/service-api'
            } | Should -Throw $Error
        }

        It 'rejects environment names longer than 255 characters' {
            $tooLongEnvironmentName = 'a' * 256

            {
                Set-GitHubSecret `
                    -Name 'DEPLOY_TOKEN' `
                    -Value $script:SecretValue `
                    -Scope Environment `
                    -Repository 'octo-org/service-api' `
                    -Environment $tooLongEnvironmentName
            } | Should -Throw '*may not exceed 255 characters*'

            {
                Remove-GitHubSecret `
                    -Name 'DEPLOY_TOKEN' `
                    -Scope Environment `
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
                -Scope Environment `
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
                Set-GitHubSecret -Name 'OVERSIZED_SECRET' -Value $tooLargeValue -Scope Repository -Repository 'octo-org/service-api'
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

            $result = Set-GitHubSecret -Name 'EXISTING_SECRET' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api'

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

            $result = Set-GitHubSecret -Name 'EXISTING_SECRET' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api' -Force

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

            $result = Set-GitHubSecret -Name 'NEW_SECRET' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'set' } -Times 0
        }

        It 'throws a clear error when gh is not installed' {
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith { $null }

            {
                Set-GitHubSecret -Name 'REST_SECRET' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api' -Token $script:TokenValue
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
                Set-GitHubSecret -Name 'REDACTION_TEST' -Value $script:SecretValue -Scope Repository -Repository 'octo-org/service-api' -Token $redactionToken
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

        It 'uses the resolved gh executable path for gh-backed requests' {
            $helpers = Import-GitHubHelperForTest

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith {
                [PSCustomObject]@{
                    Name = 'gh'
                    Source = 'Invoke-TestGhBinary'
                    Path = 'Invoke-TestGhBinary'
                    Definition = 'Invoke-TestGhBinary'
                }
            }

            Mock -CommandName gh -MockWith {
                throw 'Bare gh should not be invoked.'
            }

            Mock -CommandName Invoke-TestGhBinary -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"REGION","value":"us-east-1","visibility":"private"}'
                }

                throw "Unexpected resolved gh arguments: $($args -join ' ')"
            }

            $transport = & $helpers.ResolveTransport
            $result = & $helpers.InvokeGitHubRequest `
                -Method 'GET' `
                -BaseUri 'https://api.github.com' `
                -Path '/repos/octo-org/service-api/actions/variables/REGION' `
                -Transport $transport `
                -AuthContext ([PSCustomObject]@{
                    Token = $null
                    Source = 'ExistingGhAuth'
                    TokenEnvironmentVariableName = 'GH_TOKEN'
                }) `
                -Body $null `
                -MaxRetryCount 0 `
                -InitialRetryDelaySeconds 1 `
                -Activity 'Get GitHub variable REGION' `
                -SensitiveValues @()

            $result.name | Should -Be 'REGION'
        }

        It 'uses the resolved git executable path when discovering the current repository' {
            $helpers = Import-GitHubHelperForTest

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'git' } -MockWith {
                [PSCustomObject]@{
                    Name = 'git'
                    Source = 'Invoke-TestGitBinary'
                    Path = 'Invoke-TestGitBinary'
                    Definition = 'Invoke-TestGitBinary'
                }
            }

            Mock -CommandName git -MockWith {
                throw 'Bare git should not be invoked.'
            }

            Mock -CommandName Invoke-TestGitBinary -MockWith {
                $global:LASTEXITCODE = 0
                return 'https://github.com/octo-org/service-api.git'
            }

            $result = & $helpers.ResolveCurrentRepository

            $result.NameWithOwner | Should -Be 'octo-org/service-api'
        }

        It 'quotes native process arguments that contain spaces' {
            $helpers = Import-GitHubHelperForTest

            $quoted = & $helpers.QuoteNativeProcessArgument -Argument 'Production Blue'

            $quoted | Should -Be '"Production Blue"'
        }

        It 'uses GH_ENTERPRISE_TOKEN for gh requests to enterprise hosts' {
            $helpers = Import-GitHubHelperForTest
            $script:ObservedGhToken = $null
            $script:ObservedEnterpriseToken = $null

            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'gh' } -MockWith {
                [PSCustomObject]@{
                    Name = 'gh'
                    Source = 'Invoke-TestGhBinary'
                    Path = 'Invoke-TestGhBinary'
                    Definition = 'Invoke-TestGhBinary'
                }
            }

            Mock -CommandName Invoke-TestGhBinary -MockWith {
                $script:ObservedGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
                $script:ObservedEnterpriseToken = [Environment]::GetEnvironmentVariable('GH_ENTERPRISE_TOKEN', 'Process')
                $global:LASTEXITCODE = 0
                return '{"viewer":{"login":"octocat"}}'
            }

            $previousGhToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
            $previousGhEnterpriseToken = [Environment]::GetEnvironmentVariable('GH_ENTERPRISE_TOKEN', 'Process')

            try
            {
                $transport = & $helpers.ResolveTransport
                $null = & $helpers.InvokeGitHubRequest `
                    -Method 'GET' `
                    -BaseUri 'https://git.example.com/api/v3' `
                    -Path '/user' `
                    -Transport $transport `
                    -AuthContext ([PSCustomObject]@{
                        Token = 'enterprise-token'
                        Source = 'Parameter'
                        TokenEnvironmentVariableName = 'GH_TOKEN'
                    }) `
                    -Body $null `
                    -MaxRetryCount 0 `
                    -InitialRetryDelaySeconds 1 `
                    -Activity 'Get enterprise user' `
                    -SensitiveValues @()
            }
            finally
            {
                [Environment]::SetEnvironmentVariable('GH_TOKEN', $previousGhToken, 'Process')
                [Environment]::SetEnvironmentVariable('GH_ENTERPRISE_TOKEN', $previousGhEnterpriseToken, 'Process')
            }

            $script:ObservedGhToken | Should -BeNullOrEmpty
            $script:ObservedEnterpriseToken | Should -Be 'enterprise-token'
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

            $result = Remove-GitHubSecret -Name 'MISSING_SECRET' -Scope Repository -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'AlreadyAbsent'
            $result.Changed | Should -BeFalse
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'delete' } -Times 0
        }

        It 'disables gh interactive prompts during deletion' {
            $script:ObservedPromptDisabled = $null

            Mock -CommandName gh -MockWith {
                $script:ObservedPromptDisabled = [Environment]::GetEnvironmentVariable('GH_PROMPT_DISABLED', 'Process')

                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"TO_DELETE","updated_at":"2025-01-01T00:00:00Z"}'
                }

                if ($args[0] -eq 'secret' -and $args[1] -eq 'delete')
                {
                    $global:LASTEXITCODE = 0
                    return @()
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubSecret -Name 'TO_DELETE' -Scope Repository -Repository 'octo-org/service-api'

            $result.Status | Should -Be 'Removed'
            $script:ObservedPromptDisabled | Should -Be '1'
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

            $result = Remove-GitHubSecret -Name 'TO_DELETE' -Scope Repository -Repository 'octo-org/service-api' -WhatIf

            $result.Status | Should -Be 'WhatIf'
            Assert-MockCalled -CommandName gh -ParameterFilter { $args[0] -eq 'secret' -and $args[1] -eq 'delete' } -Times 0
        }

        It 'supports user scope deletion through -Scope User' {
            $script:CapturedDeleteArguments = $null

            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 0
                    return '{"name":"DEVCONTAINER_PAT","updated_at":"2025-01-01T00:00:00Z"}'
                }

                if ($args[0] -eq 'secret' -and $args[1] -eq 'delete')
                {
                    $script:CapturedDeleteArguments = @($args)
                    $global:LASTEXITCODE = 0
                    return @()
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubSecret -Name 'DEVCONTAINER_PAT' -Scope User

            $result.Status | Should -Be 'Removed'
            $script:CapturedDeleteArguments | Should -Contain '--user'
            $script:CapturedDeleteArguments | Should -Not -Contain '--app'
        }

        It 'supports organization scope during removal through -Scope Organization' {
            Mock -CommandName gh -MockWith {
                if ($args[0] -eq 'api')
                {
                    $global:LASTEXITCODE = 1
                    return 'HTTP 404: Not Found'
                }

                throw "Unexpected gh arguments: $($args -join ' ')"
            }

            $result = Remove-GitHubSecret -Name 'ORG_SECRET' -Scope Organization -Organization 'octo-org'

            $result.Status | Should -Be 'AlreadyAbsent'
            $result.Scope | Should -Be 'Organization'
            $result.Target | Should -Be 'organization octo-org'
        }
    }
}
