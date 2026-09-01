#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Install-PlatformPackage.ps1"
    . "$PSScriptRoot/PlatformPackageTestHelpers.ps1"
}

Describe 'Install-PlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Package manager parameter support' {
        It 'rejects winget interactive mode for other package managers' {
            $runner = & $script:NewPackageCommandRunner @{}

            { Install-PlatformPackage -PackageManager brew -Name git -Interactive -CommandRunner $runner -Confirm:$false } |
                Should-Throw -ExceptionMessage "*Parameter -Interactive*package manager 'brew'*only supported by winget*"

            $script:Invocations.Count | Should-Be 0
        }

        It 'rejects NoSudo for package managers that do not use sudo' {
            $runner = & $script:NewPackageCommandRunner @{}

            { Install-PlatformPackage -PackageManager winget -Name Git.Git -NoSudo -CommandRunner $runner -Confirm:$false } |
                Should-Throw -ExceptionMessage "*Parameter -NoSudo*package manager 'winget'*only supported by apt and apk*"

            $script:Invocations.Count | Should-Be 0
        }
    }

    Context 'Direct installs' {
        It 'installs a winget package name as an exact id and streams command output' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -Output @('winget install output')
            }

            $result = Install-PlatformPackage -PackageManager winget -Name Git.Git -CommandRunner $runner -Confirm:$false

            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' }).StreamOutput | Should-BeTruthy
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'winget install output' } -Times 1
        }

        It 'passes interactive mode to winget installs' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements --interactive' = Get-TestCommandResponse -Output @('winget interactive install output')
            }

            $result = Install-PlatformPackage -PackageManager winget -Name Git.Git -Interactive -CommandRunner $runner -Confirm:$false

            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements --interactive' }).StreamOutput | Should-BeTruthy
        }

        It 'promotes the full failure message into informational results' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget install --id Microsoft.Edge --exact --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -ExitCode -1978335090 -Output @()
            }

            $result = Install-PlatformPackage -PackageManager winget -Name Microsoft.Edge -CommandRunner $runner -Confirm:$false -WarningAction SilentlyContinue

            $result.Installed | Should-Be 0
            $result.Failed | Should-Be 1
            $result.Results[0].Message | Should-MatchString 'winget install --id Microsoft.Edge --exact'
            $result.Results[0].Message | Should-MatchString 'failed with exit code -1978335090'
            $result.Results[0].InformationalOutput | Should-BeCollection -Count 1
            $result.Results[0].InformationalOutput[0] | Should-BeString $result.Results[0].Message -CaseSensitive
            $result.InformationalResults | Should-BeCollection -Count 1
            $result.InformationalResults[0].Lines | Should-BeCollection -Count 1
            $result.InformationalResults[0].Lines[0] | Should-BeString $result.Results[0].Message -CaseSensitive
        }

        It 'does not expose a separate Id parameter' {
            $command = Get-Command Install-PlatformPackage

            $command.Parameters.ContainsKey('Name') | Should-BeTruthy
            $command.Parameters.ContainsKey('Id') | Should-BeFalsy
        }

        It 'honors WhatIf for direct installs' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew install git' = Get-TestCommandResponse -Output @('brew install git output')
            }

            $result = Install-PlatformPackage -PackageManager brew -Name git -CommandRunner $runner -WhatIf

            $result.Installed | Should-Be 0
            $result.Skipped | Should-Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).Count | Should-Be 0
        }

        It 'captures post-install instructions in the result object' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew install python' = Get-TestCommandResponse -Output @(
                    'Installing python...'
                    '==> Caveats'
                    'Python is installed as'
                    '  /opt/homebrew/bin/python3'
                )
            }

            $result = Install-PlatformPackage -PackageManager brew -Name python -CommandRunner $runner -Confirm:$false

            $result.Installed | Should-Be 1
            $result.Results[0].CapturedOutput | Should-ContainCollection 'Installing python...'
            $result.Results[0].InformationalOutput | Should-ContainCollection '==> Caveats'
            $result.InformationalResults.Count | Should-Be 1
            $result.InformationalResults[0].Lines | Should-ContainCollection 'Python is installed as'
        }
    }

    Context 'Query-driven installs' {
        It 'installs the selected search result from the interactive picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae code' = Get-TestCommandResponse -Output @()
                'brew search --casks code' = Get-TestCommandResponse -Output @('visual-studio-code')
                'brew install --cask visual-studio-code' = Get-TestCommandResponse -Output @('brew cask install output')
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Install-PlatformPackage -PackageManager brew -Query code -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 1
            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew install --cask visual-studio-code' }).StreamOutput | Should-BeTruthy
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -like '*CONTROLS*' } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$([char]0x25C7) PACKAGE DETAILS" } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter install  V details  A toggle all' } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "1-1 of 1 visible  $([char]0x00B7)  1 total  $([char]0x00B7)  1 selected" } -Times 1
            $escapeCharacter = [String][Char]27
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;37m" } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;244m" } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[0m" } -Times 1
        }

        It 'installs the current search result when Enter is pressed without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
                'brew install git' = Get-TestCommandResponse -Output @('brew install git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = Install-PlatformPackage -PackageManager brew -Query git -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 1
            $result.NotSelected | Should-Be 0
            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).StreamOutput | Should-BeTruthy
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  Enter install  V details  A toggle all' } -Times 1
        }

        It 'shows keyboard help from the query result picker' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('?', [ConsoleKey]::Oem2, $true, $false, $false)
                [System.ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Install-PlatformPackage -PackageManager brew -Query git -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 0
            $result.Installed | Should-Be 0
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$([char]0x25C8) NAVIGATION" } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$([char]0x25C2) RETURN" } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Install-PlatformPackage Help' } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Enter: ' } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'install selected packages, or the current package if none are selected' } -Times 1
        }

        It 'shows and skips an installed Homebrew search result' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae jq' = Get-TestCommandResponse -Output @('jq')
                'brew search --casks jq' = Get-TestCommandResponse -Output @()
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('jq 1.7.1')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = Install-PlatformPackage -PackageManager brew -Query jq -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 1
            $result.Installed | Should-Be 0
            $result.Skipped | Should-Be 1
            $result.Results[0].Message | Should-Be 'Package is already installed'
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install jq' }).Count | Should-Be 0
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Current: jq' } -Times 1
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "Id: jq  $([char]0x2022)  Source: homebrew/core  $([char]0x2022)  Publisher: Homebrew  $([char]0x2022)  Installed: yes" } -Times 1
            $escapeCharacter = [String][Char]27
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq "$escapeCharacter[38;5;244m" } -Times 2
        }

        It 'installs only the visible package when filtering duplicate winget ids by source' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                            }
                        )
                    }
                    @{
                        SourceDetails = @{
                            Name = 'msstore'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget install --id Git.Git --exact --source msstore --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -Output @('winget install output')
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = Install-PlatformPackage -PackageManager winget -Query git -FilterSource msstore -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 1
            $result.Installed | Should-Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements' }).Count | Should-Be 0
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --source msstore --accept-source-agreements --accept-package-agreements' }).StreamOutput | Should-BeTruthy
        }

        It 'toggles interactive mode for the current winget picker row' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{ Name = 'winget' }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '2.45.1'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetListJson = @{ Sources = @(@{ Packages = @() }) } | ConvertTo-Json -Depth 4 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements --interactive' = Get-TestCommandResponse -Output @('winget interactive install output')
            }
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('i', [ConsoleKey]::I, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = { return $keys.Dequeue() }.GetNewClosure()

            $result = Install-PlatformPackage -PackageManager winget -Query git -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements --interactive' }).StreamOutput | Should-BeTruthy
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Keys: Space select  I interactive installer  Enter install  V details  A toggle all' } -Times 2
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match '^\s+Sel\s+UI\s+' } -Times 2
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -match '^> \[ \] \[I\]' } -Times 1
        }

        It 'does not suppress terminal echo when a custom key reader drives winget details' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $wingetShowJson = @{
                DefaultLocale = @{
                    Description = 'Distributed version control system'
                }
            } | ConvertTo-Json -Depth 4 -Compress
            $runner = & $script:NewPackageCommandRunner @{
                'winget search git --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetShowJson)
            }
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            $result = Install-PlatformPackage -PackageManager winget -Query git -CommandRunner $runner -KeyReader $keyReader -TerminalEchoController $terminalEchoController -Confirm:$false

            $result.Selected | Should-Be 0
            $echoActions.Count | Should-Be 0
            Should-Invoke -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
        }

        It 'restores terminal echo when winget details throw in the console key reader flow' -Skip:($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) {
            $wingetSearchJson = @{
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
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress
            $searchResponse = Get-TestCommandResponse -Output @($wingetSearchJson)
            $listResponse = Get-TestCommandResponse -Output @($wingetListJson)
            $runner = {
                param(
                    [Parameter(Mandatory)]
                    [String]$Command,

                    [Parameter()]
                    [String[]]$Arguments = @(),

                    [Parameter()]
                    [Switch]$StreamOutput
                )

                $key = "$Command $($Arguments -join ' ')".Trim()
                if ($key -eq 'winget search git --accept-source-agreements --output json')
                {
                    return $searchResponse
                }

                if ($key -eq 'winget list --accept-source-agreements --output json')
                {
                    return $listResponse
                }

                if ($key -eq 'winget show --id Git.Git --exact --accept-source-agreements --output json')
                {
                    throw 'winget details failed'
                }

                return [PSCustomObject]@{
                    ExitCode = 127
                    Output = @("Unexpected command: $key")
                }
            }.GetNewClosure()
            $keyReader = & $script:NewKeyReader -Values @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
            )
            $echoActions = New-Object 'System.Collections.Generic.List[Object]'
            $terminalEchoController = & $script:NewTerminalEchoController -Actions $echoActions

            {
                Install-PlatformPackage -PackageManager winget -Query git -CommandRunner $runner -KeyReader $keyReader -TreatKeyReaderAsConsoleKeyReader -TerminalEchoController $terminalEchoController -Confirm:$false
            } | Should-Throw -ExceptionMessage '*winget details failed*'

            ($echoActions -join '|') | Should-Be 'Disable|Restore:saved-stty-state'
        }

        It 'keeps picker table rows within the current console width' {
            $wingetSearchJson = @{
                Sources = @(
                    @{
                        SourceDetails = @{
                            Name = 'winget'
                        }
                        Packages = @(
                            @{
                                PackageName = 'Git'
                                PackageIdentifier = 'Git.Git'
                                Version = '17.0.1010.2'
                                Source = 'homebrew/core'
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
            $wingetListJson = @{
                Sources = @(
                    @{
                        Packages = @()
                    }
                )
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget search sql --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetSearchJson)
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -Output @($wingetListJson)
            }
            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Install-PlatformPackage -PackageManager winget -Query sql -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $tableLines = @(
                $script:HostOutput |
                ForEach-Object { ([String]::Join('', [String[]]$_)) -replace "$([Char]27)\[[0-9;]*m", '' } |
                Where-Object {
                    $_ -match '^\s+Sel\s+' -or
                    $_ -match '^[> ] \[[ x]\]\s+'
                }
            )

            $tableLines.Count | Should-BeGreaterThan 1
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should-MatchString '\bVer\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should-MatchString '\bTyp\b'
            ($tableLines | Where-Object { $_ -match '^\s+Sel\s+' } | Select-Object -First 1) | Should-MatchString '\bSrc\b'
            ($tableLines | Where-Object { $_ -match '^[> ] \[[ x]\]\s+' } | Select-Object -First 1) | Should-MatchString 'homebrew/core'
            (($tableLines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum) | Should-BeLessThanOrEqual (Get-TestPickerLineLimit)
        }

        It 'returns a no-selection summary when the picker is cancelled' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Install-PlatformPackage -PackageManager brew -Query git -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should-Be 0
            $result.NotSelected | Should-Be 1
            $result.Installed | Should-Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).Count | Should-Be 0
        }
    }

    Context 'Pipeline installs' {
        It 'skips packages already marked as installed' {
            $package = [PSCustomObject]@{
                Name = 'openssl'
                Id = 'openssl'
                PackageManager = 'apt'
                Type = 'amd64'
                Version = '3.0.2-0ubuntu1.15'
                Installed = $true
            }

            $result = $package | Install-PlatformPackage -CommandRunner (& $script:NewPackageCommandRunner @{}) -Confirm:$false

            $result.Selected | Should-Be 1
            $result.Skipped | Should-Be 1
            $result.Results[0].Message | Should-Be 'Package is already installed'
        }

        It 'passes the package source to winget install commands' {
            $package = [PSCustomObject]@{
                Name = 'Git'
                Id = 'Git.Git'
                PackageManager = 'winget'
                Type = 'Package'
                Version = '2.44.0'
                Source = 'msstore'
                Installed = $false
            }
            $runner = & $script:NewPackageCommandRunner @{
                'winget install --id Git.Git --exact --source msstore --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -Output @('winget install output')
            }

            $result = $package | Install-PlatformPackage -CommandRunner $runner -Confirm:$false

            $result.Installed | Should-Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --source msstore --accept-source-agreements --accept-package-agreements' }).StreamOutput | Should-BeTruthy
        }
    }
}
