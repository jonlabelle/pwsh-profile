#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Find-SystemPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Install-SystemPackage.ps1"

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
                [String[]]$Arguments = @(),

                [Parameter()]
                [Switch]$StreamOutput
            )

            $key = "$Command $($Arguments -join ' ')".Trim()
            $localInvocations.Add([PSCustomObject]@{
                    Command = $Command
                    Arguments = @($Arguments)
                    Key = $key
                    StreamOutput = $StreamOutput.IsPresent
                })

            if ($localResponses.ContainsKey($key))
            {
                return $localResponses[$key]
            }

            return [PSCustomObject]@{
                ExitCode = 127
                Output = @("Unexpected command: $key")
            }
        }.GetNewClosure()
    }
}

Describe 'Find-SystemPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutputRecords = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {
            param(
                [Object]$Object,
                [ConsoleColor]$ForegroundColor
            )

            $script:HostOutput.Add($Object)
            $script:HostOutputRecords.Add([PSCustomObject]@{
                    Object = $Object
                    ForegroundColor = $ForegroundColor
                })
        }
        Mock -CommandName Clear-Host -MockWith {}
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

            $result = @(Find-SystemPackage -PackageManager winget -NonInteractive -Query git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'Git'
            $result[0].Id | Should -Be 'Git.Git'
            $result[0].Version | Should -Be '2.45.1'
            $result[0].Description | Should -Be 'Distributed version control system'
        }

        It 'marks search results as installed from winget list output' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                                CatalogName = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.44.0'
                                Source = 'winget'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }

            $result = @(Find-SystemPackage -PackageManager winget -NonInteractive -Query git -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Installed | Should -BeTrue
        }
    }

    Context 'Homebrew search' {
        It 'returns formula and cask results from separate searches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
            }

            $result = @(Find-SystemPackage -PackageManager brew -NonInteractive -Query git -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 3
            ($result | Where-Object { $_.Name -eq 'git' }).Type | Should -Be 'Formula'
            ($result | Where-Object { $_.Name -eq 'git-credential-manager' }).Type | Should -Be 'Cask'
        }

        It 'marks formula search results as installed from Homebrew list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae jq' = Get-TestCommandResponse -Output @('gojq', 'jq', 'jq-lsp')
                'brew search --casks jq' = Get-TestCommandResponse -Output @('jquake')
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('jq 1.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Find-SystemPackage -PackageManager brew -NonInteractive -Query jq -CommandRunner $runner -Top 0)

            ($result | Where-Object { $_.Name -eq 'jq' }).Installed | Should -BeTrue
            ($result | Where-Object { $_.Name -eq 'gojq' }).Installed | Should -BeFalse
            ($result | Where-Object { $_.Name -eq 'jquake' }).Installed | Should -BeFalse
        }

        It 'keeps formula results when cask search reports no Homebrew matches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae 7zip' = Get-TestCommandResponse -Output @('7zip')
                'brew search --casks 7zip' = Get-TestCommandResponse -ExitCode 1 -Output @('Error: No formulae or casks found for "7zip".')
            }

            $result = @(Find-SystemPackage -PackageManager brew -NonInteractive -Query 7zip -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be '7zip'
            $result[0].Type | Should -Be 'Formula'
        }

        It 'keeps cask results when formula search reports no Homebrew matches' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae code' = Get-TestCommandResponse -ExitCode 1 -Output @('Error: No formulae found for "code".')
                'brew search --casks code' = Get-TestCommandResponse -Output @('visual-studio-code')
            }

            $result = @(Find-SystemPackage -PackageManager brew -NonInteractive -Query code -CommandRunner $runner -Top 0)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'visual-studio-code'
            $result[0].Type | Should -Be 'Cask'
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

            $result = @(Find-SystemPackage -PackageManager apt -NonInteractive -Query openssl -CommandRunner $runner)

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

            $result = @(Find-SystemPackage -PackageManager apk -NonInteractive -Query bash -CommandRunner $runner -Top 0)

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

            $result = @(Find-SystemPackage -PackageManager brew -NonInteractive -Query git -ExcludePackage 'git-lfs' -Top 1 -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }
    }

    Context 'interactive remote search UI' {
        It 'prompts for a query and renders remote registry results by default' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @('git-credential-manager')
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Find-SystemPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search: git' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Spacebar: select  I: install current/selected*' } -Times 1
            @($script:HostOutputRecords | Where-Object { $_.ForegroundColor -eq [ConsoleColor]::DarkGray -and $_.Object -like '*git*' }).Count | Should -Be 1
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 5
        }

        It 'allows a new query to be entered from the interactive browser' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
                'brew search --formulae code' = Get-TestCommandResponse -Output @()
                'brew search --casks code' = Get-TestCommandResponse -Output @('visual-studio-code')
            }

            $queries = [System.Collections.Generic.Queue[String]]::new()
            @('git', 'code') | ForEach-Object { $queries.Enqueue($_) }
            $queryReader = {
                return $queries.Dequeue()
            }.GetNewClosure()

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('s', [ConsoleKey]::S, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Find-SystemPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew search --formulae git' }).Count | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew search --casks code' }).Count | Should -Be 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search: code' } -Times 1
        }

        It 'returns selected packages when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git', 'git-lfs')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $queryReader = {
                'git'
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Find-SystemPackage -PackageManager brew -PassThru -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Spacebar: select  Enter: return selected  I: install current/selected*' } -Times 1
        }

        It 'installs the selected package from the interactive browser' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
                'brew install git' = Get-TestCommandResponse -Output @('brew install git output')
            }

            $queryReader = {
                'git'
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('i', [ConsoleKey]::I, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Find-SystemPackage -PackageManager brew -CommandRunner $runner -QueryReader $queryReader -KeyReader $keyReader

            $result.Selected | Should -Be 1
            $result.Installed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew install git output' } -Times 1
        }
    }
}
