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
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*Dependencies*' } -Times 1
    }

    It 'exposes ShouldProcess safety switches for delegated operations' {
        $command = Get-Command -Name Show-PlatformPackageManager

        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
    }

    It 'routes installed package browsing through Show-InstalledPlatformPackage' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0', 'gh 2.50.0')
            'brew list --cask --versions' = Get-TestCommandResponse -Output @()
        }
        $promptReader = & $script:NewPromptReader @('1', 'g*', 'gh', 'q')
        $keyReader = {
            [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
        }

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader -KeyReader $keyReader)

        $result.Count | Should -Be 0
        @($script:Invocations | Where-Object { $_.Key -eq 'brew list --formula --versions' }).Count | Should -Be 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage - Homebrew' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*git*' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*gh*' } -Times 0
    }

    It 'installs a direct package id from the manager' {
        $runner = & $script:NewPackageCommandRunner @{
            'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -Output @('winget install output')
        }
        $promptReader = & $script:NewPromptReader @('3', 'id', 'Git.Git', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should -Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' }).StreamOutput | Should -BeTrue
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'winget install output' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Insta\s*lled' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Details' } -Times 1
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
        $promptReader = & $script:NewPromptReader @('2', 'git', '', 'q')

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
        $promptReader = & $script:NewPromptReader @('4', 'Git', '', 'y', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager winget -SkipRefresh -UninstallPrevious -CommandRunner $runner -PromptReader $promptReader)

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
        $promptReader = & $script:NewPromptReader @('5', 'visual-studio-code', '', 'y', 'q')

        $result = @(
            & {
                $ConfirmPreference = 'None'
                Show-PlatformPackageManager -PackageManager brew -Purge -CommandRunner $runner -PromptReader $promptReader
            }
        )

        $result.Count | Should -Be 0
        ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall --cask --zap visual-studio-code' }).StreamOutput | Should -BeTrue
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew zap output' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'Removed' } -Times 1
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
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Enter/M: menu  1-6: run another action  Q: quit' } -Times 1
    }
}
