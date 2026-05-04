#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-PlatformPackageManager.ps1"

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
            [Parameter(Mandatory)]
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
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    It 'renders the unified menu and exits when quit is selected' {
        $promptReader = & $script:NewPromptReader @('q')

        $result = @(Show-PlatformPackageManager -PromptReader $promptReader)

        $result.Count | Should -Be 0
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-PlatformPackageManager' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq '  1. Browse installed packages' } -Times 1
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq '  6. Inspect package dependencies' } -Times 1
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
        ($script:HostOutput -join "`n") | Should -Match 'Insta\s*lled'
    }

    It 'shows dependency records from the manager' {
        $runner = & $script:NewPackageCommandRunner @{
            'brew deps --direct git' = Get-TestCommandResponse -Output @('gettext')
        }
        $promptReader = & $script:NewPromptReader @('6', 'git', '1', 'n', 'q')

        $result = @(Show-PlatformPackageManager -PackageManager brew -CommandRunner $runner -PromptReader $promptReader)

        $result.Count | Should -Be 0
        ($script:HostOutput -join "`n") | Should -BeLike '*Relationship*'
        Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*git -> gettext*' } -Times 1
    }
}
