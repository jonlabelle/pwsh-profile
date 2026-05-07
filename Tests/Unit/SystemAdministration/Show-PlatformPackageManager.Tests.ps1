#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-PlatformPackageManager.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Install-PlatformPackage.ps1"

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

            return Get-TestCommandResponse -ExitCode 127 -Output @("Unexpected command: $key")
        }.GetNewClosure()
    }

    $script:NewPromptReader = {
        param(
            [Parameter()]
            [String[]]$Values
        )

        $queue = [System.Collections.Generic.Queue[String]]::new()
        $Values | ForEach-Object { $queue.Enqueue($_) }

        return {
            param(
                [Parameter()]
                [String]$Prompt
            )

            if ($queue.Count -eq 0)
            {
                throw "Unexpected prompt: $Prompt"
            }

            return $queue.Dequeue()
        }.GetNewClosure()
    }

    $script:NewKeyReader = {
        param(
            [Parameter()]
            [System.ConsoleKeyInfo[]]$Values
        )

        $queue = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
        $Values | ForEach-Object { $queue.Enqueue($_) }

        return {
            if ($queue.Count -eq 0)
            {
                throw 'Unexpected key read'
            }

            return $queue.Dequeue()
        }.GetNewClosure()
    }
}

Describe 'Show-PlatformPackageManager' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    It 'renders the unified menu and exits when quit is selected' {
        $promptReader = & $script:NewPromptReader @('q')

        $result = @(Show-PlatformPackageManager -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Manager: Auto -> *' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Installed packages*' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Direct install*' } -Times 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Dependencies*' } -Times 1
    }

    It 'exposes ShouldProcess safety switches for delegated operations' {
        $command = Get-Command -Name Show-PlatformPackageManager

        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
    }

    It 'routes installed package browsing through Show-InstalledPlatformPackage without extra prompts' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'gh 2.50.0')
            'brew list --cask --versions' = Get-TestCommandResponse -Output @()
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('1', [ConsoleKey]::D1, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            [System.ConsoleKeyInfo]::new([Char]27, [ConsoleKey]::Escape, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should -Be 0
        @($script:Invocations | Where-Object { $_.Key -eq 'brew list --formula --versions' }).Count | Should -Be 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage - Homebrew' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*git*' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*gh*' } -Times 1
    }

    It 'does not expose direct install as a manager action' {
        $promptReader = & $script:NewPromptReader @('3', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Direct install*' } -Times 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Choose 1, 2, 4-6 or Q.' } -Times 1
    }

    It 'supports arrow key navigation in the manager menu' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('git')
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new([Char]0, [ConsoleKey]::DownArrow, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Install-PlatformPackage -ParameterFilter {
            $Query -eq 'git' -and
            $PackageManager -eq 'apt' -and
            $NoSudo
        } -Times 1
    }

    It 'routes search installs through Install-PlatformPackage with NoSudo forwarded' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Install-PlatformPackage -ParameterFilter {
            $Query -eq 'git' -and
            $PackageManager -eq 'apt' -and
            $NoSudo -and
            $Top -eq 50
        } -Times 1
    }

    It 'routes upgrade options and forwards winget uninstall-previous' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
            'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                'Name               Id                          Version Available Source'
                '-----------------------------------------------------------------------'
                'Git                Git.Git                     2.43.0  2.44.0    winget'
            )
            'winget upgrade --id Git.Git --exact --accept-package-agreements --accept-source-agreements --uninstall-previous' = Get-TestCommandResponse -Output @('winget upgrade output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('4', [ConsoleKey]::D4, $false, $false, $false)
            [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -UninstallPrevious -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should -Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'winget upgrade --id Git.Git --exact --accept-package-agreements --accept-source-agreements --uninstall-previous' }).StreamOutput | Should -BeTrue
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'winget upgrade output' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Upgraded' } -Times 1
    }

    It 'routes remove options and forwards purge behavior' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @()
            'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            'brew uses --installed visual-studio-code' = Get-TestCommandResponse -Output @()
            'brew uninstall --cask --zap visual-studio-code' = Get-TestCommandResponse -Output @('brew zap output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('5', [ConsoleKey]::D5, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(
            & {
                $ConfirmPreference = 'None'
                Show-PlatformPackageManager -PackageManager brew -Purge -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader
            }
        )

        $result.Count | Should -Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall --cask --zap visual-studio-code' }).StreamOutput | Should -BeTrue
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew zap output' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Removed' } -Times 1
    }

    It 'shows a green status indicator after a successful upgrade' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
            'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                'Name               Id                          Version Available Source'
                '-----------------------------------------------------------------------'
                'Git                Git.Git                     2.43.0  2.44.0    winget'
            )
            'winget upgrade --id Git.Git --exact --accept-package-agreements --accept-source-agreements' = Get-TestCommandResponse -Output @('winget upgrade output')
        }
        $promptReader = & $script:NewPromptReader @()
        $keyReader = & $script:NewKeyReader @(
            [System.ConsoleKeyInfo]::new('4', [ConsoleKey]::D4, $false, $false, $false)
            [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
            [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
        )

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Upgraded: 1' -and $ForegroundColor -eq 'Green' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Failed: 0' -and $ForegroundColor -eq 'Green' } -Times 1
    }

    It 'shows a green status indicator after a successful install' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 1
                Selected = 1
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 1' -and $ForegroundColor -eq 'Green' } -Times 1
    }

    It 'shows a red status indicator when an operation has failures' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 2
                Selected = 2
                NotSelected = 0
                Installed = 1
                Skipped = 0
                Failed = 1
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 1' -and $ForegroundColor -eq 'Red' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Failed: 1' -and $ForegroundColor -eq 'Red' } -Times 1
    }

    It 'shows a yellow status indicator when packages were skipped but none failed' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 3
                Selected = 3
                NotSelected = 0
                Installed = 2
                Skipped = 1
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -NoSudo -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Installed: 2' -and $ForegroundColor -eq 'Yellow' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Skipped: 1' -and $ForegroundColor -eq 'Yellow' } -Times 1
    }

    It 'does not show a status indicator for dependency lookups' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('6', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Installed:|Upgraded:|Removed:' } -Times 0
    }

    It 'returns directly to the menu without a result screen when a search query is cancelled' {
        $promptReader = & $script:NewPromptReader @('2', '', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search and Install Packages' } -Times 0
    }

    It 'returns directly to the menu without a result screen when no packages are selected in the picker' {
        Mock -CommandName Install-PlatformPackage -MockWith {
            [PSCustomObject]@{
                PackageManager = 'apt'
                PackageManagerDisplayName = 'APT'
                TotalMatched = 5
                Selected = 0
                NotSelected = 5
                Installed = 0
                Skipped = 0
                Failed = 0
                Results = @()
            }
        }
        $promptReader = & $script:NewPromptReader @('2', 'git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager apt -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Install-PlatformPackage -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Search and Install Packages' } -Times 0
    }

    It 'shows dependency records from the manager' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('6', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Relationship*' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*git -> gettext*' } -Times 1
    }

    It 'explains that winget reverse dependency lookup is unavailable' {
        $promptReader = & $script:NewPromptReader @('6', 'Git.Git', '2', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*winget does not expose reverse dependency metadata*' } -Times 1
    }

    It 'keeps action results on a dedicated screen until the next action is chosen' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('6', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Platform Package Manager' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Package Dependencies' } -Times 1
    }
}
