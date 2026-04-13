#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Upgrade-Package.ps1"

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

Describe 'Upgrade-Package' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Homebrew package discovery' {
        It 'returns formula and cask update records from JSON output' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @(
                    @{
                        name = 'visual-studio-code'
                        installed_versions = @('1.88.0')
                        current_version = '1.89.0'
                        auto_updates = $false
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = @(Upgrade-Package -PackageManager brew -SkipRefresh -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 2

            $formula = $result | Where-Object { $_.Name -eq 'git' }
            $formula.PackageManager | Should -Be 'brew'
            $formula.Type | Should -Be 'Formula'
            $formula.InstalledVersion | Should -Be '2.43.0'
            $formula.LatestVersion | Should -Be '2.44.0'
            (@($formula.UpgradeArguments) -join '|') | Should -Be 'upgrade|git'

            $cask = $result | Where-Object { $_.Name -eq 'visual-studio-code' }
            $cask.Type | Should -Be 'Cask'
            (@($cask.UpgradeArguments) -join '|') | Should -Be 'upgrade|--cask|visual-studio-code'
        }

        It 'streams refresh and upgrade command output when upgrading all packages' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew update' = Get-TestCommandResponse -Output @('brew update output')
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -Output @('brew upgrade git output')
            }

            $result = Upgrade-Package -PackageManager brew -All -CommandRunner $runner -Confirm:$false

            $result.Upgraded | Should -Be 1
            $result.Failed | Should -Be 0
            $result.NotSelected | Should -Be 0

            ($script:Invocations | Where-Object { $_.Key -eq 'brew update' }).StreamOutput | Should -BeTrue
            ($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).StreamOutput | Should -BeTrue

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew update output' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'brew upgrade git output' } -Times 1
        }

        It 'reports streamed command failures with command context when captured output is unavailable' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -ExitCode 42 -Output @()
            }

            $result = Upgrade-Package -PackageManager brew -SkipRefresh -All -CommandRunner $runner -Confirm:$false -WarningAction SilentlyContinue

            $result.Failed | Should -Be 1
            $result.Skipped | Should -Be 0
            $result.NotSelected | Should -Be 0
            $result.Results[0].Message | Should -Match 'brew upgrade git failed with exit code 42'
            $result.Results[0].Message | Should -Match 'streamed directly to the console'
        }

        It 'does not read stale LASTEXITCODE for unstructured command runner output' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $lastExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

            try
            {
                $global:LASTEXITCODE = 42

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

                    if ($key -eq 'brew outdated --json=v2')
                    {
                        return [PSCustomObject]@{
                            ExitCode = 0
                            Output = @($brewJson)
                        }
                    }

                    if ($key -eq 'brew upgrade git')
                    {
                        return 'brew upgrade git output'
                    }

                    return [PSCustomObject]@{
                        ExitCode = 127
                        Output = @("Unexpected command: $key")
                    }
                }.GetNewClosure()

                $result = Upgrade-Package -PackageManager brew -SkipRefresh -All -CommandRunner $runner -Confirm:$false

                $result.Upgraded | Should -Be 1
                $result.Failed | Should -Be 0
                $result.Results[0].ExitCode | Should -Be 0
            }
            finally
            {
                if ($lastExitCode)
                {
                    $global:LASTEXITCODE = $lastExitCode.Value
                }
                else
                {
                    Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Linux package discovery' {
        It 'parses apt upgradable package output' {
            $runner = & $script:NewPackageCommandRunner @{
                'apt list --upgradable' = Get-TestCommandResponse -Output @(
                    'Listing... Done'
                    'openssl/jammy-updates 3.0.2-0ubuntu1.15 arm64 [upgradable from: 3.0.2-0ubuntu1.14]'
                )
            }

            $result = @(Upgrade-Package -PackageManager apt -SkipRefresh -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'openssl'
            $result[0].PackageManager | Should -Be 'apt'
            $result[0].InstalledVersion | Should -Be '3.0.2-0ubuntu1.14'
            $result[0].LatestVersion | Should -Be '3.0.2-0ubuntu1.15'
            (@($result[0].UpgradeArguments) -join '|') | Should -Be 'install|--only-upgrade|-y|openssl'
        }

        It 'parses apk version output and keeps hyphenated package names' {
            $runner = & $script:NewPackageCommandRunner @{
                'apk version -l <' = Get-TestCommandResponse -Output @(
                    'busybox-1.36.1-r19 < 1.36.1-r20'
                    'py3-requests-2.31.0-r0 < 2.32.0-r0'
                )
            }

            $result = @(Upgrade-Package -PackageManager apk -SkipRefresh -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 2

            $busybox = $result | Where-Object { $_.Name -eq 'busybox' }
            $busybox.InstalledVersion | Should -Be '1.36.1-r19'
            $busybox.LatestVersion | Should -Be '1.36.1-r20'
            (@($busybox.UpgradeArguments) -join '|') | Should -Be 'add|--upgrade|busybox'

            $requests = $result | Where-Object { $_.Name -eq 'py3-requests' }
            $requests.InstalledVersion | Should -Be '2.31.0-r0'
            $requests.LatestVersion | Should -Be '2.32.0-r0'
        }
    }

    Context 'Interactive package selection' {
        It 'treats Ctrl+C as a cancel command' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                        pinned = $false
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
                'brew upgrade git' = Get-TestCommandResponse -Output @('brew upgrade git output')
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = Upgrade-Package -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -Confirm:$false

            $result.Selected | Should -Be 0
            $result.NotSelected | Should -Be 1
            $result.Upgraded | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
        }

        It 'renders only the current viewport for long upgrade lists' {
            $brewJson = @{
                formulae = @(
                    @{ name = 'pkg-01'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-02'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-03'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                    @{ name = 'pkg-04'; installed_versions = @('1.0.0'); current_version = '1.1.0' }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Upgrade-Package -PackageManager brew -SkipRefresh -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2 -Confirm:$false

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }
    }

    Context 'winget package discovery' {
        It 'falls back to table parsing when JSON output is unavailable' {
            $runner = & $script:NewPackageCommandRunner @{
                'winget upgrade --accept-source-agreements --output json' = Get-TestCommandResponse -ExitCode 1 -Output @('Unrecognized argument: --output')
                'winget upgrade --accept-source-agreements' = Get-TestCommandResponse -Output @(
                    'Name               Id                          Version Available Source'
                    '-----------------------------------------------------------------------'
                    'PowerShell         Microsoft.PowerShell        7.4.1   7.4.2     winget'
                    'Git                Git.Git                     2.43.0  2.44.0    winget'
                    '27 package(s) have version numbers that cannot be determined. Use --include-unknown to see all results.'
                )
            }

            $result = @(Upgrade-Package -PackageManager winget -SkipRefresh -AsObject -CommandRunner $runner)

            $result.Count | Should -Be 2

            $powershell = $result | Where-Object { $_.Name -eq 'PowerShell' }
            $powershell.Id | Should -Be 'Microsoft.PowerShell'
            $powershell.InstalledVersion | Should -Be '7.4.1'
            $powershell.LatestVersion | Should -Be '7.4.2'
            (@($powershell.UpgradeArguments) -join '|') | Should -Be 'upgrade|--id|Microsoft.PowerShell|--exact|--accept-package-agreements|--accept-source-agreements'
        }
    }

    Context 'Filtering and dry runs' {
        It 'applies include and exclude filters to package names and ids' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                    }
                    @{
                        name = 'node'
                        installed_versions = @('21.0.0')
                        current_version = '22.0.0'
                    }
                    @{
                        name = 'git-lfs'
                        installed_versions = @('3.4.0')
                        current_version = '3.5.0'
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = @(Upgrade-Package -PackageManager brew -SkipRefresh -AsObject -IncludePackage 'git*' -ExcludePackage 'git-lfs' -CommandRunner $runner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
        }

        It 'honors -WhatIf for refresh and upgrade commands' {
            $brewJson = @{
                formulae = @(
                    @{
                        name = 'git'
                        installed_versions = @('2.43.0')
                        current_version = '2.44.0'
                    }
                )
                casks = @()
            } | ConvertTo-Json -Depth 6 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'brew outdated --json=v2' = Get-TestCommandResponse -Output @($brewJson)
            }

            $result = Upgrade-Package -PackageManager brew -All -WhatIf -CommandRunner $runner

            $result | Should -Not -BeNullOrEmpty
            $result.Selected | Should -Be 1
            $result.NotSelected | Should -Be 0
            $result.Upgraded | Should -Be 0
            $result.Skipped | Should -Be 1

            @($script:Invocations | Where-Object { $_.Key -eq 'brew update' }).Count | Should -Be 0
            @($script:Invocations | Where-Object { $_.Key -eq 'brew upgrade git' }).Count | Should -Be 0
        }
    }
}
