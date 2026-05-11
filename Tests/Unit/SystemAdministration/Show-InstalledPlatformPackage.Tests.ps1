#Requires -Modules Pester

BeforeAll {
    $Global:ProgressPreference = 'SilentlyContinue'

    . "$PSScriptRoot/../../../Functions/SystemAdministration/Show-InstalledPlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Get-PlatformPackageDependency.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Remove-PlatformPackage.ps1"
    . "$PSScriptRoot/../../../Functions/SystemAdministration/Upgrade-PlatformPackage.ps1"

    $script:NewTestCommandResponse = {
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
        $newTestCommandResponse = $script:NewTestCommandResponse

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

            return & $newTestCommandResponse -ExitCode 127 -Output @("Unexpected command: $key")
        }.GetNewClosure()
    }
}

Describe 'Show-InstalledPlatformPackage' {
    BeforeEach {
        $script:Invocations = New-Object 'System.Collections.Generic.List[Object]'
        $script:HostOutput = New-Object 'System.Collections.Generic.List[Object]'
        Mock -CommandName Write-Host -MockWith { $script:HostOutput.Add($Object) }
        Mock -CommandName Clear-Host -MockWith {}
    }

    Context 'Object output' {
        It 'returns installed packages as objects when NonInteractive is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -NonInteractive -CommandRunner $runner)

            $result.Count | Should -Be 2
            ($result | Where-Object { $_.Name -eq 'git' }).InstalledVersion | Should -Be '2.44.0'
            ($result | Where-Object { $_.Name -eq 'git' }).Publisher | Should -Be 'Homebrew'
        }
    }

    Context 'Interactive browsing' {
        It 'returns no output when cancelled' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'D: deps  V: details  R: remove  U: upgrade  F: [all]  Arrow keys/Home/End/PgUp/PgDn: navigate  ?: help  Ctrl+C/Q/Esc: exit' } -Times 1
            @($script:HostOutput | Where-Object { [String]::IsNullOrEmpty([String]$_) }).Count | Should -Be 3
        }

        It 'does not exit when Enter is pressed in browse mode' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'D: deps  V: details  R: remove  U: upgrade  F: [all]  Arrow keys/Home/End/PgUp/PgDn: navigate  ?: help  Ctrl+C/Q/Esc: exit' } -Times 2
        }

        It 'renders only the current viewport for long package lists' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @(
                        'pkg-01 1.0.0'
                        'pkg-02 1.0.0'
                        'pkg-03 1.0.0'
                        'pkg-04 1.0.0'
                    ))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            }

            $null = Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PickerPageSize 2

            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-01*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-02*' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-03*' } -Times 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like '*pkg-04*' } -Times 0
        }

        It 'returns selected packages when PassThru is used' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -like 'Spacebar: select*' } -Times 1
        }

        It 'returns the current package when PassThru is used without a selection' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @('visual-studio-code 1.89.0'))
            }

            $keyReader = {
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            }

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Spacebar: select  Enter: return current/selected  A: toggle all  D: deps  V: details  R: remove  U: upgrade  F: [all]  S: [All]  Arrow keys/Home/End/PgUp/PgDn: navigate  ?: help  Ctrl+C/Q/Esc: exit' } -Times 1
        }

        It 'shows keyboard help from the picker when question mark is pressed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
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

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage Help' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'D: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'open or close the dependency view for the current package' -and $ForegroundColor -eq 'DarkGray' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'B: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'return to the package list from the dependency view' -and $ForegroundColor -eq 'DarkGray' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'V: ' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'load a missing winget description when available' -and $ForegroundColor -eq 'DarkGray' } -Times 1
        }

        It 'loads missing winget descriptions only when V is pressed' {
            $wingetListJson = @{
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
            $wingetShowJson = @{
                DefaultLocale = @{
                    Description = 'Distributed version control system'
                }
            } | ConvertTo-Json -Depth 4 -Compress

            $runner = & $script:NewPackageCommandRunner @{
                'winget list --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetListJson))
                'winget show --id Git.Git --exact --accept-source-agreements --output json' = (& $script:NewTestCommandResponse -Output @($wingetShowJson))
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager winget -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: <press V to load>' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: retrieving description...' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Description: Distributed version control system' } -Times 1
            @($script:Invocations | Where-Object { $_.Key -eq 'winget show --id Git.Git --exact --accept-source-agreements --output json' }).Count | Should -Be 1
        }

        It 'shows both dependency directions from the picker with D' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Get-PlatformPackageDependency -MockWith {
                param(
                    [Object[]]$Package,
                    [String]$Direction,
                    [String]$PackageManager,
                    [ScriptBlock]$CommandRunner
                )

                if ($Direction -eq 'DependsOn')
                {
                    return @([PSCustomObject]@{ RelatedPackage = 'gettext'; DependencyType = 'Dependency'; Installed = $true })
                }

                return @([PSCustomObject]@{ RelatedPackage = 'curl'; DependencyType = 'Dependent'; Installed = $true })
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('d', [ConsoleKey]::D, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'DependsOn' } -Times 1
            Assert-MockCalled -CommandName Get-PlatformPackageDependency -ParameterFilter { $Direction -eq 'RequiredBy' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Show-InstalledPlatformPackage Dependencies - Homebrew' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn + RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [DependsOn]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Dependencies [RequiredBy]' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Press B/Backspace/LeftArrow to return to the package list.' } -Times 1
        }

        It 'invokes Remove-PlatformPackage from the picker when R is confirmed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Remove-PlatformPackage -MockWith {
                [PSCustomObject]@{
                    Removed = 1
                    Failed = 0
                    Skipped = 0
                }
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('r', [ConsoleKey]::R, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Remove-PlatformPackage -ParameterFilter {
                $PackageManager -eq 'brew' -and
                $All -and
                @($IncludePackage).Count -eq 1 -and
                @($IncludePackage)[0] -eq 'git'
            } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Status: Removed: 1, Failed: 0, Skipped: 0' } -Times 1
        }

        It 'invokes Upgrade-PlatformPackage from the picker when U is confirmed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            Mock -CommandName Upgrade-PlatformPackage -MockWith {
                [PSCustomObject]@{
                    Upgraded = 1
                    Failed = 0
                    Skipped = 0
                }
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('u', [ConsoleKey]::U, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]3, [ConsoleKey]::C, $false, $false, $true)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader)

            $result.Count | Should -Be 0
            Assert-MockCalled -CommandName Upgrade-PlatformPackage -ParameterFilter {
                $PackageManager -eq 'brew' -and
                $All -and
                $SkipRefresh -and
                @($IncludePackage).Count -eq 1 -and
                @($IncludePackage)[0] -eq 'git'
            } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Status: Upgraded: 1, Failed: 0, Skipped: 0' } -Times 1
        }

        It 'filters picker results by package name when F is pressed' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'curl 8.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('g', [ConsoleKey]::G, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'git'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: g' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[g\]' } -Times 1
        }

        It 'treats lowercase q as filter text instead of cancel' {
            $runner = & $script:NewPackageCommandRunner @{
                'brew list --formula --versions' = (& $script:NewTestCommandResponse -Output @('git 2.44.0', 'jq 1.7.1'))
                'brew list --cask --versions' = (& $script:NewTestCommandResponse -Output @())
            }

            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            @(
                [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false)
                [System.ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
                [System.ConsoleKeyInfo]::new([Char]13, [ConsoleKey]::Enter, $false, $false, $false)
            ) | ForEach-Object { $keys.Enqueue($_) }
            $keyReader = {
                return $keys.Dequeue()
            }.GetNewClosure()

            $result = @(Show-InstalledPlatformPackage -PackageManager brew -CommandRunner $runner -KeyReader $keyReader -PassThru)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'jq'
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -eq 'Current filter: q' } -Times 1
            Assert-MockCalled -CommandName Write-Host -ParameterFilter { $Object -match 'F: \[q\]' } -Times 1
        }
    }
}
