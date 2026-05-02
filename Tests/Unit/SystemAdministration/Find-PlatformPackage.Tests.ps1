#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Find-PlatformPackage.ps1"

    function Get-TestCommandResponse
    {
        param(
            [Parameter()]
            [Int32]$ExitCode = 0,

            [Parameter()]
            [String[]]$Output = @()
        )

        [PSCustomObject]@{
            ExitCode = $ExitCode
            Output = @($Output)
        }
    }

    $script:NewPackageCommandRunner = {
        param(
            [Parameter(Mandatory)]
            [Hashtable]$Responses
        )

        $localResponses = $Responses
        $localInvocations = $script:Invocations

        return {
            param(
                [Parameter(Mandatory)]
                [String]$Command,

                [Parameter()]
                [String[]]$Arguments = @()
            )

            $key = "$Command $($Arguments -join ' ')".Trim()
            $localInvocations.Add([PSCustomObject]@{
                Command = $Command
                Arguments = @($Arguments)
                Key = $key
            })

            if ($localResponses.ContainsKey($key))
            {
                return $localResponses[$key]
            }

            return Get-TestCommandResponse -ExitCode 127 -Output @("Unexpected command: $key")
        }.GetNewClosure()
    }
}

Describe 'Find-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
    }

    Context 'winget search' {
        It 'returns normalized results from JSON output' {
            $wingetJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                CatalogName = 'winget'
                                Description = 'Distributed version control system'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetJson)
            }

            $result = @(Find-PlatformPackage -PackageManager winget -Query git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Git'
            $result[0].Id | Should -Be 'Git.Git'
            $result[0].Version | Should -Be '2.45.1'
            $result[0].Description | Should -Be 'Distributed version control system'
        }
    }

    Context 'Homebrew search' {
        It 'returns formula and cask results from separate searches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -Query git -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 3
            ($result | Where-Object { $_.Name -eq 'git' }).Type | Should -Be 'Formula'
            ($result | Where-Object { $_.Name -eq 'git-credential-manager' }).Type | Should -Be 'Cask'
        }
    }

    Context 'APT search' {
        It 'parses package descriptions and installed state' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt search --names-only openssl' = Get-TestCommandResponse -Output @(
                    'Sorting... Done'
                    'Full Text Search... Done'
                    'openssl/jammy-updates 3.0.2-0ubuntu1.15 amd64 [installed,automatic]'
                    '  Secure Sockets Layer toolkit - cryptographic utility'
                )
            }

            $result = @(Find-PlatformPackage -PackageManager apt -Query openssl -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].Installed | Should -BeTrue
            $result[0].Notes | Should -Be 'Automatic'
            $result[0].Description | Should -Be 'Secure Sockets Layer toolkit - cryptographic utility'
        }
    }

    Context 'apk search' {
        It 'parses versioned results and installed markers' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk search --description bash' = Get-TestCommandResponse -Output @(
                    'bash-5.2.15-r5 -- GNU Bourne Again shell [installed]'
                    'bash-doc-5.2.15-r5 -- Documentation for bash'
                )
            }

            $result = @(Find-PlatformPackage -PackageManager apk -Query bash -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'bash' }).Installed | Should -BeTrue
            ($result | Where-Object { $_.Name -eq 'bash-doc' }).Version | Should -Be '5.2.15-r5'
        }
    }

    Context 'result limiting and filtering' {
        It 'applies exclusions and top limits after normalization' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
            }

            $result = @(Find-PlatformPackage -PackageManager brew -Query git -ExcludePackage 'git-lfs' -Top 1 -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }
    }
}
