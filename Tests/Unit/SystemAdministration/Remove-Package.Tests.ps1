#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Remove-Package.ps1"

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
}

Describe 'Remove-Package' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask records from list output' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Remove-Package -PackageManager brew -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should -Be 'brew'
            $formula.Type | Should -Be 'Formula'
            $formula.InstalledVersion | Should -Be '2.44.0'
            (@($formula.RemoveArguments) -join '|') | Should -Be 'uninstall|git'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should -Be 'Cask'
            (@($cask.RemoveArguments) -join '|') | Should -Be 'uninstall|--cask|visual-studio-code'
        }

        It 'uses zap for casks when purge is requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @()
                'brew list --cask --versions' = Get-TestCommandResponse -Output @('visual-studio-code 1.89.0')
            }

            $result = @(Remove-Package -PackageManager brew -AsObject -Purge -CommandRunner $runner)

            (@($result[0].RemoveArguments) -join '|') | Should -Be 'uninstall|--cask|--zap|visual-studio-code'
        }

        It 'streams remove command output when removing all matching packages' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $result = Remove-Package -PackageManager brew -IncludePackage git -All -CommandRunner $runner -Confirm:$false

            $result.Removed | Should -Be 1
            $result.Failed | Should -Be 0
            $result.NotSelected | Should -Be 0

            ($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).StreamOutput | Should -BeTrue

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew uninstall git output' } -Times 1
        }

        It 'does not remove every installed package with -All unless an include filter is supplied' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            { Remove-Package -PackageManager brew -All -CommandRunner $runner -Confirm:$false } |
            Should -Throw -ExpectedMessage '*without an include filter*'
        }
    }

    Context 'Linux package discovery' {
        It 'parses apt installed package output and uses purge when requested' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --installed' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates,now 3.0.2-0ubuntu1.15 arm64 [installed,automatic]'
                )
            }

            $result = @(Remove-Package -PackageManager apt -AsObject -Purge -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].PackageManager | Should -Be 'apt'
            $result[0].InstalledVersion | Should -Be '3.0.2-0ubuntu1.15'
            $result[0].Notes | Should -Be 'Automatic'
            (@($result[0].RemoveArguments) -join '|') | Should -Be 'purge|-y|openssl'
        }

        It 'parses apk package output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk info -v' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19'
                    'py3-requests-2.31.0-r0'
                )
            }

            $result = @(Remove-Package -PackageManager apk -AsObject -Purge -CommandRunner $runner)

            $result.Count | Should -Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should -Be '1.36.1-r19'
            (@($busybox.RemoveArguments) -join '|') | Should -Be 'del|--purge|busybox'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should -Be '2.31.0-r0'
        }
    }

    Context 'Interactive package selection' {
        It 'treats Ctrl+C as a cancel command' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
                'brew uninstall git' = Get-TestCommandResponse -Output @('brew uninstall git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Remove-Package -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.NotSelected | Should -Be 1
            $result.Removed | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
        }
    }

    Context 'winget package discovery' {
        It 'falls back to table parsing when JSON output is unavailable' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget list --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Source'
                    '--------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.2   winget'
                    'Git                Git.Git                     2.44.0  winget'
                )
            }

            $result = @(Remove-Package -PackageManager winget -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 2

            $powershell = $result | Where-Object { $_.Name -eq 'PowerShell' }
            $powershell.Id | Should -Be 'Microsoft.PowerShell'
            $powershell.InstalledVersion | Should -Be '7.4.2'
            (@($powershell.RemoveArguments) -join '|') | Should -Be 'uninstall|--id|Microsoft.PowerShell|--exact|--accept-source-agreements'
        }
    }

    Context 'Filtering and dry runs' {
        It 'applies include and exclude filters to package names and ids' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @(
                    'git 2.44.0'
                    'node 22.0.0'
                    'git-lfs 3.5.0'
                )
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = @(Remove-Package -PackageManager brew -AsObject -IncludePackage 'git*' -ExcludePackage 'git-lfs' -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }

        It 'honors -WhatIf for remove commands' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = Get-TestCommandResponse -Output @('git 2.44.0')
                'brew list --cask --versions' = Get-TestCommandResponse -Output @()
            }

            $result = Remove-Package -PackageManager brew -IncludePackage git -All -WhatIf -CommandRunner $runner

            $result | Should -Not -BeNullOrEmpty
            $result.Selected | Should -Be 1
            $result.NotSelected | Should -Be 0
            $result.Removed | Should -Be 0
            $result.Skipped | Should -Be 1

            @($script:Invocations | Where-Object { $_.Key -eq 'brew uninstall git' }).Count | Should -Be 0
        }
    }
}
