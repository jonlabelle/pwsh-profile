#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

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

Describe 'Install-SystemPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Direct installs' {
        It 'installs a winget package by id and streams command output' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' = Get-TestCommandResponse -Output @('winget install output')
            }

            $result = Install-SystemPackage -PackageManager winget -Id Git.Git -CommandRunner $runner -Confirm:$false

            $result.Installed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'winget install output' } -Times 1
        }

        It 'honors WhatIf for direct installs' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew install git' = Get-TestCommandResponse -Output @('brew install git output')
            }

            $result = Install-SystemPackage -PackageManager brew -Name git -CommandRunner $runner -WhatIf

            $result.Installed | Should -Be 0
            $result.Skipped | Should -Be 1
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).Count | Should -Be 0
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

            $result = Install-SystemPackage -PackageManager brew -Query code -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 1
            $result.Installed | Should -Be 1
            ($script:Invocations | Where-Object { $_.Key -eq 'brew install --cask visual-studio-code' }).StreamOutput | Should -BeTrue
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Spacebar: select*' } -Times 1
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

            $result = Install-SystemPackage -PackageManager brew -Query jq -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 1
            $result.Installed | Should -Be 0
            $result.Skipped | Should -Be 1
            $result.Results[0].Message | Should -Be 'Package is already installed'
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install jq' }).Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current: jq | Id: jq | Installed: yes' } -Times 1
        }

        It 'returns a no-selection summary when the picker is cancelled' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew search --formulae git' = Get-TestCommandResponse -Output @('git')
                'brew search --casks git' = Get-TestCommandResponse -Output @()
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Install-SystemPackage -PackageManager brew -Query git -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.NotSelected | Should -Be 1
            $result.Installed | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew install git' }).Count | Should -Be 0
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

            $result = $package | Install-SystemPackage -CommandRunner (& $script:NewPackageCommandRunner @{}) -Confirm:$false

            $result.Selected | Should -Be 1
            $result.Skipped | Should -Be 1
            $result.Results[0].Message | Should -Be 'Package is already installed'
        }
    }
}
