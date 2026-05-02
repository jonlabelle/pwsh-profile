#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-SystemPackage.ps1"

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

Describe 'Get-SystemPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask records from list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Get-SystemPackage -PackageManager brew -CommandRunner $runner)

            $result.Count | Should -Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should -Be 'brew'
            $formula.Type | Should -Be 'Formula'
            $formula.InstalledVersion | Should -Be '2.44.0'
            $formula.PSObject.Properties.Name | Should -Not -Contain 'RemoveArguments'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should -Be 'Cask'
            $cask.Source | Should -Be 'homebrew/cask'
        }
    }

    Context 'Winget package discovery' {
        It 'returns installed packages from JSON output' {
            $wingetJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetJson)
            }

            $result = @(Get-SystemPackage -PackageManager winget -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Git'
            $result[0].Id | Should -Be 'Git.Git'
            $result[0].InstalledVersion | Should -Be '2.45.1'
            $result[0].Source | Should -Be 'winget'
        }
    }

    Context 'Linux package discovery' {
        It 'parses apt installed package output and keeps automatic state in notes' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates,now 3.0.2-0ubuntu1.15 arm64 [installed,automatic]'
                )
            }

            $result = @(Get-SystemPackage -PackageManager apt -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].Type | Should -Be 'arm64'
            $result[0].InstalledVersion | Should -Be '3.0.2-0ubuntu1.15'
            $result[0].Notes | Should -Be 'Automatic'
        }

        It 'parses apk output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19'
                    'py3-requests-2.31.0-r0'
                )
            }

            $result = @(Get-SystemPackage -PackageManager apk -CommandRunner $runner)

            $result.Count | Should -Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should -Be '1.36.1-r19'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should -Be '2.31.0-r0'
        }
    }

    Context 'Filtering' {
        It 'filters by include and exclude patterns against name or id' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'gh 2.51.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Get-SystemPackage -PackageManager brew -Name 'g*' -ExcludePackage 'gh' -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }
    }
}
